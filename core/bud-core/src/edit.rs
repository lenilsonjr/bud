//! Every edit the views make, as a file operation first and an index change second (ADR-001 §5).
//!
//! The file system step runs before the index is touched, so a failed write or rename changes no
//! row. A bud is a Markdown file plus an optional sibling folder of the same name that holds its
//! children; operations that move or rename the file carry the folder with it, and the rows of
//! every descendant follow.

use crate::attachments;
use crate::frontmatter;
use crate::lock;
use crate::scan;
use crate::{
    insert_row, links, tags, Error, Kind, Place, Placement, Properties, Result, State, Vault,
};
use crate::{read_bud, Bud, SELECT};
use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

const TRASH: &str = ".trash";

/// The longest file name, in bytes, less room for a taken name's " 99", the ".md" and the dot and
/// ".tmp" of the file [`write_atomic`] writes first.
const MAX_NAME: usize = 255 - ". 99.md.tmp".len();

/// A title as a file name: `/ \ : * ? " < > |`, control characters and leading dots become a
/// space, then the ends are trimmed. A name too long for the file system is cut on a character
/// boundary and loses the spaces and dots it then ends with. Nothing left means "Untitled".
pub fn sanitize_filename(title: &str) -> String {
    let replaced: String = title
        .chars()
        .map(|c| {
            if "/\\:*?\"<>|".contains(c) || c.is_control() {
                ' '
            } else {
                c
            }
        })
        .collect();
    let mut name = replaced.trim();
    loop {
        let next = name.trim_start_matches('.').trim();
        if next.len() == name.len() {
            break;
        }
        name = next;
    }
    if name.len() > MAX_NAME {
        let mut end = MAX_NAME;
        while !name.is_char_boundary(end) {
            end -= 1;
        }
        name = name[..end].trim_end_matches([' ', '.']);
    }
    if name.is_empty() {
        "Untitled".to_string()
    } else {
        name.to_string()
    }
}

/// `1970-01-01T00:00:00Z` for second zero.
fn iso_utc(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    // Days since the epoch to a civil date (proleptic Gregorian).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

fn now_iso() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    iso_utc(secs)
}

/// Write `text` to a temp file in the same folder, then rename it over `target`.
pub(crate) fn write_atomic(target: &Path, text: &str) -> std::io::Result<()> {
    // A dot name, which a scan skips, in the same folder so the rename stays on one volume.
    let mut name = std::ffi::OsString::from(".");
    name.push(target.file_name().unwrap_or_default());
    name.push(".tmp");
    let tmp = target.with_file_name(name);
    std::fs::write(&tmp, text)?;
    if let Err(err) = std::fs::rename(&tmp, target) {
        let _ = std::fs::remove_file(&tmp);
        return Err(err);
    }
    Ok(())
}

pub(crate) fn mtime_of(path: &Path) -> i64 {
    std::fs::metadata(path)
        .ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// `a/b.md` → `a/b`; a folder bud's path is already its folder.
fn dir_of(path: &str) -> &str {
    path.strip_suffix(".md").unwrap_or(path)
}

fn join(dir: &str, name: &str) -> String {
    if dir.is_empty() {
        name.to_string()
    } else {
        format!("{dir}/{name}")
    }
}

/// Folders created on the way to `dir` that no file claims are buds of their own, as a rescan
/// would find them; give each a row.
fn ensure_folders(root: &Path, conn: &Connection, dir: &str) -> Result<()> {
    let mut acc = String::new();
    for (i, part) in dir.split('/').filter(|p| !p.is_empty()).enumerate() {
        let parent_dir = acc.clone();
        acc = join(&acc, part);
        if i == 0 && scan::RESERVED.contains(&part) {
            continue;
        }
        if scan::sibling_file(root, Path::new(&acc)).exists() {
            continue;
        }
        let known: Option<i64> = conn
            .query_row("SELECT 1 FROM buds WHERE path = ?1", params![acc], |r| {
                r.get(0)
            })
            .optional()?;
        if known.is_some() {
            continue;
        }
        let parent = scan::parent_bud(root, Path::new(&parent_dir));
        let row = Placement {
            path: &acc,
            parent: parent.as_deref(),
            title: part,
            place: scan::place_of(Path::new(&acc)),
            mtime: mtime_of(&root.join(&acc)),
        };
        insert_row(conn, &row, &Properties::default(), None, "")?;
    }
    Ok(())
}

impl Vault {
    /// Create `<parent folder>/<title>.md`: the root for none, `Inbox`, `Archive` or `Warehouse` for a place,
    /// else the folder beside the parent bud's file, made when it is not there yet. The file has
    /// `created` now, `state: open` for a to-do, `source` when given and an empty body. A taken
    /// name gets " 2", " 3". Returns the new bud's path.
    pub fn create(
        &mut self,
        parent: Option<&str>,
        title: &str,
        kind: Kind,
        source: Option<&str>,
    ) -> Result<String> {
        self.make(parent, title, kind, source, None)
    }

    /// `create` with the `from` key already in the first write, so a planted bud is never
    /// on disk without it.
    fn make(
        &mut self,
        parent: Option<&str>,
        title: &str,
        kind: Kind,
        source: Option<&str>,
        from: Option<&str>,
    ) -> Result<String> {
        let dir = self.parent_dir(parent)?;
        let base = sanitize_filename(title);
        std::fs::create_dir_all(self.root.join(&dir))?;
        let mut name = base.clone();
        let mut n = 2;
        while self.taken(&join(&dir, &name)) {
            name = format!("{base} {n}");
            n += 1;
        }
        let path = format!("{}.md", join(&dir, &name));
        let props = Properties {
            state: (kind == Kind::Todo).then_some(State::Open),
            created: Some(now_iso()),
            source: source.map(str::to_string),
            from: from.map(str::to_string),
            ..Default::default()
        };
        let text = frontmatter::write("", &props);
        let absolute = self.root.join(&path);
        write_atomic(&absolute, &text)?;

        let bud_parent = scan::parent_bud(&self.root, Path::new(&dir));
        let row = Placement {
            path: &path,
            parent: bud_parent.as_deref(),
            title: &name,
            place: scan::place_of(Path::new(&path)),
            mtime: mtime_of(&absolute),
        };
        lock(&self.written).insert(path.clone(), row.mtime);
        let mut conn = lock(&self.conn);
        let tx = conn.transaction()?;
        ensure_folders(&self.root, &tx, &dir)?;
        insert_row(&tx, &row, &props, None, "")?;
        tx.commit()?;
        Ok(path)
    }

    /// Replace the body of a bud and keep its frontmatter byte for byte. A bud that is only a
    /// folder gets its file first.
    pub fn set_body(&mut self, path: &str, text: &str) -> Result<()> {
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        let mut path = path.to_string();
        if !path.ends_with(".md") {
            self.set_properties(&path, &Properties::default())?;
            path.push_str(".md");
        }
        let absolute = self.root.join(&path);
        let old = std::fs::read_to_string(&absolute)?;
        let (yaml, body) = frontmatter::split(&old);
        let head = &old[..old.len() - body.len()];
        write_atomic(&absolute, &format!("{head}{text}"))?;
        let mtime = mtime_of(&absolute);
        lock(&self.written).insert(path.clone(), mtime);
        let mut conn = lock(&self.conn);
        let tx = conn.transaction()?;
        tx.execute(
            "UPDATE buds SET body = ?1, mtime = ?2 WHERE path = ?3",
            params![text, mtime, path],
        )?;
        links::relink(&tx, &path, text)?;
        tags::retag(&tx, &path, yaml, text)?;
        tx.commit()?;
        Ok(())
    }

    /// Rename a bud: its file and its sibling folder together, and every descendant row follows.
    /// Returns the new path. A name that is taken is an error.
    pub fn rename(&mut self, path: &str, new_title: &str) -> Result<String> {
        let dir = dir_of(path);
        let parent_dir = dir.rsplit_once('/').map_or("", |(parent, _)| parent);
        let new_dir = join(parent_dir, &sanitize_filename(new_title));
        self.relocate(path, &new_dir)
    }

    /// Move a bud under `new_parent` (a bud's path, `Inbox`, `Archive`, `Warehouse`, or none for the root),
    /// with its folder and descendants. Returns the new path. Moving a bud into itself or one of
    /// its own descendants is an error.
    pub fn move_to(&mut self, path: &str, new_parent: Option<&str>) -> Result<String> {
        let parent_dir = self.parent_dir(new_parent)?;
        let dir = dir_of(path);
        let leaf = dir.rsplit_once('/').map_or(dir, |(_, leaf)| leaf);
        let new_dir = join(&parent_dir, leaf);
        self.relocate(path, &new_dir)
    }

    /// Move a bud and its folder to `.trash/<same relative path>`. The rows get `place = trash`.
    pub fn trash(&mut self, path: &str) -> Result<()> {
        if dir_of(path) == TRASH || path.starts_with(".trash/") {
            return Err(Error::Invalid(format!("already in the trash: {path}")));
        }
        self.relocate(path, &join(TRASH, dir_of(path)))?;
        Ok(())
    }

    /// Move a trashed bud and its folder back to where it was. Returns the restored path.
    pub fn restore(&mut self, path: &str) -> Result<String> {
        let old_dir = dir_of(path);
        let Some(new_dir) = old_dir.strip_prefix(".trash/") else {
            return Err(Error::Invalid(format!("not in the trash: {path}")));
        };
        let restored = self.relocate(path, new_dir)?;
        self.prune_trash(old_dir)?;
        Ok(restored)
    }

    /// Remove a trashed bud for good: its file and its folder first, then its row and every row
    /// below it. A bud outside the trash is refused. Its document stays until the next sync, which
    /// deletes it from the tree; a peer that merges that tree removes the bud from its own trash.
    pub fn delete_forever(&mut self, path: &str) -> Result<()> {
        if !dir_of(path).starts_with(".trash/") {
            return Err(Error::Invalid(format!("not in the trash: {path}")));
        }
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        self.purge(path)
    }

    /// Remove a bud's file, its folder and their rows. A file already gone counts as removed. When
    /// the folder cannot be removed whole, the rows of what did go below it are dropped before the
    /// error is returned, and the bud's own row stays, so a retry finds it and only what is left.
    pub(crate) fn purge(&mut self, path: &str) -> Result<()> {
        let dir = dir_of(path);
        if path.ends_with(".md") {
            match std::fs::remove_file(self.root.join(path)) {
                Err(err) if err.kind() != std::io::ErrorKind::NotFound => return Err(err.into()),
                _ => {}
            }
        }
        let folder = self.root.join(dir);
        let removed = if folder.is_dir() {
            std::fs::remove_dir_all(&folder)
        } else {
            Ok(())
        };

        {
            let mut conn = lock(&self.conn);
            let tx = conn.transaction()?;
            if removed.is_ok() {
                tx.execute(
                    "DELETE FROM buds WHERE path = ?1 OR path = ?2
                     OR substr(path, 1, length(?2) + 1) = ?2 || '/'",
                    params![path, dir],
                )?;
                attachments::remove_under(&tx, dir)?;
            } else {
                let rows: Vec<String> = {
                    let mut stmt = tx.prepare(
                        "SELECT path FROM buds WHERE path = ?1 OR path = ?2
                         OR substr(path, 1, length(?2) + 1) = ?2 || '/'",
                    )?;
                    let found = stmt.query_map(params![path, dir], |r| r.get(0))?;
                    found.collect::<std::result::Result<_, _>>()?
                };
                let gone = |row: &&String| row.as_str() != path && !self.root.join(row).exists();
                for row in rows.iter().filter(gone) {
                    tx.execute("DELETE FROM buds WHERE path = ?1", params![row])?;
                }
                let pictures: Vec<String> = {
                    let mut stmt = tx.prepare(
                        "SELECT path FROM attachments
                         WHERE substr(path, 1, length(?1) + 1) = ?1 || '/'",
                    )?;
                    let found = stmt.query_map(params![dir], |r| r.get(0))?;
                    found.collect::<std::result::Result<_, _>>()?
                };
                for row in pictures.iter().filter(gone) {
                    tx.execute("DELETE FROM attachments WHERE path = ?1", params![row])?;
                }
            }
            tx.commit()?;
        }
        removed?;
        self.prune_trash(dir)
    }

    /// Remove every bud in the trash for good.
    pub fn empty_trash(&mut self) -> Result<()> {
        for bud in self.roots(Place::Trash)? {
            self.delete_forever(&bud.path)?;
        }
        Ok(())
    }

    /// Folders the trash only held for the sake of the bud that left `dir` go with it, and so do
    /// their rows. A folder with a document is a bud that was trashed on purpose and stays, empty
    /// or not.
    fn prune_trash(&self, dir: &str) -> Result<()> {
        let mut dir = dir.rsplit_once('/').map_or("", |(parent, _)| parent);
        while dir.contains('/') {
            let kept: bool = lock(&self.conn).query_row(
                "SELECT EXISTS (SELECT 1 FROM docs WHERE path = ?1)",
                params![dir],
                |r| r.get(0),
            )?;
            if kept || std::fs::remove_dir(self.root.join(dir)).is_err() {
                break;
            }
            lock(&self.conn).execute("DELETE FROM buds WHERE path = ?1", params![dir])?;
            dir = dir.rsplit_once('/').map_or("", |(parent, _)| parent);
        }
        Ok(())
    }

    /// Set `state: open|done` on one bud; none removes it and makes the bud a note. Its children
    /// are untouched.
    pub fn set_state(&mut self, path: &str, state: Option<State>) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.state = state;
        self.set_properties(path, &props)
    }

    /// Pin or unpin one bud.
    pub fn set_pinned(&mut self, path: &str, pinned: bool) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.pinned = pinned;
        self.set_properties(path, &props)
    }

    /// Set `when` (`YYYY-MM-DD`) on one bud; none or an empty day removes it.
    pub fn set_when(&mut self, path: &str, when: Option<&str>) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.when = when.filter(|day| !day.is_empty()).map(str::to_string);
        self.set_properties(path, &props)
    }

    /// Set `due` (`YYYY-MM-DD`) on one bud; none or an empty day removes it.
    pub fn set_due(&mut self, path: &str, due: Option<&str>) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.due = due.filter(|day| !day.is_empty()).map(str::to_string);
        self.set_properties(path, &props)
    }

    /// Set `created` (an ISO moment, `2026-10-02T11:00:00Z`) on one bud, for a bud brought in
    /// from elsewhere that keeps the moment it was first made; none or an empty one removes it.
    pub fn set_created(&mut self, path: &str, created: Option<&str>) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.created = created
            .filter(|moment| !moment.is_empty())
            .map(str::to_string);
        self.set_properties(path, &props)
    }

    /// Set `from-state` on a planted bud (`moved 2026-11-05T21:00:00Z`, `cancelled`, `closed`,
    /// `gone`); none or an empty one removes it.
    pub fn set_from_state(&mut self, path: &str, state: Option<&str>) -> Result<()> {
        let mut props = self.properties_of(path)?;
        props.from_state = state.filter(|s| !s.is_empty()).map(str::to_string);
        self.set_properties(path, &props)
    }

    fn properties_of(&self, path: &str) -> Result<Properties> {
        let bud = self
            .bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        Ok(Properties {
            state: bud.state,
            when: bud.when,
            due: bud.due,
            pinned: bud.pinned,
            created: bud.created,
            source: bud.source,
            from: bud.from,
            from_state: bud.from_state,
        })
    }

    /// The bud planted from a source item, by its `from:` key (`mail:M1234`), if there is one
    /// outside the trash.
    pub fn planted(&self, from: &str) -> Result<Option<Bud>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(&format!(
            "{SELECT} WHERE planted_from = ?1 AND place != 'trash' ORDER BY path LIMIT 1"
        ))?;
        Ok(stmt.query_row(params![from], read_bud).optional()?)
    }

    /// Plant a source item: a new bud under `parent` (as in [`Vault::create`]) that carries
    /// `from:`. An item already planted is not planted twice: the bud that has it is returned
    /// instead. Returns the bud's path and whether it is new.
    pub fn plant(
        &mut self,
        parent: Option<&str>,
        title: &str,
        kind: Kind,
        from: &str,
    ) -> Result<(String, bool)> {
        if let Some(bud) = self.planted(from)? {
            return Ok((bud.path, false));
        }
        let path = self.make(parent, title, kind, None, Some(from))?;
        Ok((path, true))
    }

    /// The folder that holds the children of `parent`.
    pub(crate) fn parent_dir(&self, parent: Option<&str>) -> Result<String> {
        match parent {
            None => Ok(String::new()),
            Some(place @ ("Inbox" | "Archive" | "Warehouse")) => Ok(place.to_string()),
            Some(path) => {
                self.bud(path)?
                    .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
                Ok(dir_of(path).to_string())
            }
        }
    }

    /// Whether a file or a folder already has this name (path without `.md`).
    fn taken(&self, path_without_ext: &str) -> bool {
        self.root.join(format!("{path_without_ext}.md")).exists()
            || self.root.join(path_without_ext).exists()
    }

    /// Move a bud so its folder is `new_dir`. The files move first and the rows only once they
    /// have; a file that cannot move leaves every row as it was.
    fn relocate(&mut self, old: &str, new_dir: &str) -> Result<String> {
        self.bud(old)?
            .ok_or_else(|| Error::NoSuchBud(old.to_string()))?;
        let is_file = old.ends_with(".md");
        let old_dir = dir_of(old);
        let new_path = if is_file {
            format!("{new_dir}.md")
        } else {
            new_dir.to_string()
        };
        if new_path == old {
            return Ok(new_path);
        }
        if new_dir.starts_with(&format!("{old_dir}/")) {
            return Err(Error::Invalid(format!("{old} cannot move into itself")));
        }
        if self.taken(new_dir) {
            return Err(Error::Exists(new_path));
        }
        let (parent_dir, name) = new_dir.rsplit_once('/').unwrap_or(("", new_dir));
        std::fs::create_dir_all(self.root.join(parent_dir))?;

        let old_file = self.root.join(old);
        let new_file = self.root.join(&new_path);
        std::fs::rename(&old_file, &new_file)?;
        let old_folder = self.root.join(old_dir);
        if is_file && old_folder.is_dir() {
            if let Err(err) = std::fs::rename(&old_folder, self.root.join(new_dir)) {
                let _ = std::fs::rename(&new_file, &old_file);
                return Err(err.into());
            }
        }

        let rows: Vec<(String, Option<String>)> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare("SELECT path, parent FROM buds")?;
            let found = stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
            found.collect::<std::result::Result<_, _>>()?
        };
        let bud_parent = scan::parent_bud(&self.root, Path::new(parent_dir));
        let prefix = format!("{old_dir}/");
        let follow = |p: &str| -> Option<String> {
            if p == old {
                Some(new_path.clone())
            } else {
                p.strip_prefix(&prefix)
                    .map(|rest| format!("{new_dir}/{rest}"))
            }
        };
        let place = scan::place_of(Path::new(&new_path));
        let mut conn = lock(&self.conn);
        let tx = conn.transaction()?;
        ensure_folders(&self.root, &tx, parent_dir)?;
        for (path, parent) in &rows {
            let Some(path_now) = follow(path) else {
                continue;
            };
            let (parent_now, title) = if path == old {
                (bud_parent.clone(), Some(name))
            } else {
                (parent.as_deref().and_then(follow).or(parent.clone()), None)
            };
            tx.execute(
                "UPDATE buds SET path = ?1, parent = ?2, place = ?3, title = COALESCE(?4, title)
                 WHERE path = ?5",
                params![path_now, parent_now, place.as_str(), title, path],
            )?;
            tx.execute(
                "UPDATE docs SET path = ?1 WHERE path = ?2",
                params![path_now, path],
            )?;
        }
        // The pictures in the bud's folder moved with it.
        attachments::relocate(&tx, old_dir, new_dir)?;
        tx.commit()?;
        Ok(new_path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_dates() {
        assert_eq!(iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso_utc(1_700_000_000), "2023-11-14T22:13:20Z");
        assert_eq!(iso_utc(1_709_164_800), "2024-02-29T00:00:00Z");
    }
}

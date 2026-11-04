//! Links between buds: `[[Target]]` and `[[Target|label]]` written in a body. The index keeps
//! every link under the row of the bud it is written in, so a rename or a move of that bud keeps
//! its links; the target stays the text between the brackets and is resolved when it is read,
//! so planting or renaming the bud it names needs no rewrite of the index.
//!
//! A target resolves to the one bud whose title it is, then to the one bud whose title it is in
//! any case, then to the bud at that path, with or without `.md`. More than one bud at the first
//! rank that has any, or none at all, leaves the link unresolved. Trash is never a target.

use crate::{lock, Result, Vault};
use rusqlite::{params, Connection};

/// One link as written, with the bud it resolves to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Link {
    /// The bud the link is written in.
    pub from: String,
    /// The text between the brackets, without the label or a `#heading`.
    pub target: String,
    /// The text after `|`, when there is one.
    pub label: Option<String>,
    /// The bud the target names; none when no bud, or more than one, does.
    pub to: Option<String>,
}

/// The links in a body, in order: target, label, byte offset of the opening brackets. Fenced
/// code and code spans hold no links, and a link never spans lines.
pub(crate) fn parse(body: &str) -> Vec<(String, Option<String>, usize)> {
    let mut out = Vec::new();
    let mut fence: Option<&str> = None;
    let mut offset = 0;
    for line in body.split_inclusive('\n') {
        let start = offset;
        offset += line.len();
        let trimmed = line.trim_start();
        if let Some(open) = fence {
            if trimmed.starts_with(open) {
                fence = None;
            }
            continue;
        }
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            fence = Some(&trimmed[..3]);
            continue;
        }
        let bytes = line.as_bytes();
        let mut i = 0;
        let mut in_code = false;
        while i < bytes.len() {
            match bytes[i] {
                b'`' => in_code = !in_code,
                b'[' if !in_code && bytes.get(i + 1) == Some(&b'[') => {
                    if let Some(len) = line[i + 2..].find("]]") {
                        let inner = &line[i + 2..i + 2 + len];
                        if !inner.contains(['[', ']', '\n']) {
                            if let Some(found) = split(inner) {
                                out.push((found.0, found.1, start + i));
                            }
                            i += len + 4;
                            continue;
                        }
                    }
                }
                _ => {}
            }
            i += 1;
        }
    }
    out
}

/// `Target#heading|label` as its target and label; none when the target is empty.
fn split(inner: &str) -> Option<(String, Option<String>)> {
    let (target, label) = match inner.split_once('|') {
        Some((t, l)) => (t, Some(l.trim().to_string()).filter(|l| !l.is_empty())),
        None => (inner, None),
    };
    let target = target.split('#').next().unwrap_or("").trim();
    (!target.is_empty()).then(|| (target.to_string(), label))
}

/// Replace the links of the bud at `path` with the ones in `body`.
pub(crate) fn relink(conn: &Connection, path: &str, body: &str) -> Result<()> {
    let row: i64 = conn.query_row(
        "SELECT rowid FROM buds WHERE path = ?1",
        params![path],
        |r| r.get(0),
    )?;
    conn.execute("DELETE FROM links WHERE source = ?1", params![row])?;
    let mut insert = conn.prepare_cached(
        "INSERT INTO links (source, target, label, position) VALUES (?1, ?2, ?3, ?4)",
    )?;
    for (target, label, position) in parse(body) {
        insert.execute(params![row, target, label, position as i64])?;
    }
    Ok(())
}

/// The bud `target` names, by the order in the module comment.
fn resolve(conn: &Connection, target: &str) -> Result<Option<String>> {
    let mut stmt = conn.prepare_cached(
        "SELECT path, title FROM buds WHERE place != 'trash'
         AND (title = ?1 COLLATE NOCASE OR path = ?1 OR path = ?1 || '.md')",
    )?;
    let found: Vec<(String, String)> = stmt
        .query_map(params![target], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<std::result::Result<_, _>>()?;
    // The query found only buds that match by title in any case, or by path.
    let rank = |(_, title): &(String, String)| {
        if title == target {
            0
        } else if title.to_lowercase() == target.to_lowercase() {
            1
        } else {
            2
        }
    };
    let Some(best) = found.iter().map(rank).min() else {
        return Ok(None);
    };
    let mut at_best = found.into_iter().filter(|b| rank(b) == best);
    Ok(match (at_best.next(), at_best.next()) {
        (Some((path, _)), None) => Some(path),
        _ => None,
    })
}

fn read(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Link>> {
    let mut stmt = conn.prepare(sql)?;
    let rows: Vec<(String, String, Option<String>)> = stmt
        .query_map(args, |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
        .collect::<std::result::Result<_, _>>()?;
    rows.into_iter()
        .map(|(from, target, label)| {
            let to = resolve(conn, &target)?;
            Ok(Link {
                from,
                target,
                label,
                to,
            })
        })
        .collect()
}

const LINKS: &str = "SELECT buds.path, links.target, links.label FROM links
     JOIN buds ON buds.rowid = links.source WHERE buds.place != 'trash'";

impl Vault {
    /// The links written in the bud at `path`, in the order they appear.
    pub fn links(&self, path: &str) -> Result<Vec<Link>> {
        read(
            &lock(&self.conn),
            &format!("{LINKS} AND buds.path = ?1 ORDER BY links.position"),
            params![path],
        )
    }

    /// The links that resolve to the bud at `path`, by the bud they are written in.
    pub fn backlinks(&self, path: &str) -> Result<Vec<Link>> {
        let conn = lock(&self.conn);
        let Some(title) = conn
            .query_row(
                "SELECT title FROM buds WHERE path = ?1",
                params![path],
                |r| r.get::<_, String>(0),
            )
            .ok()
        else {
            return Ok(Vec::new());
        };
        let bare = path.strip_suffix(".md").unwrap_or(path);
        let found = read(
            &conn,
            &format!(
                "{LINKS} AND (links.target = ?1 COLLATE NOCASE OR links.target = ?2 OR links.target = ?3)
                 ORDER BY buds.path, links.position"
            ),
            params![title, path, bare],
        )?;
        Ok(found
            .into_iter()
            .filter(|l| l.to.as_deref() == Some(path))
            .collect())
    }

    /// Every link that names no bud, or more than one.
    pub fn unresolved_links(&self) -> Result<Vec<Link>> {
        let found = read(
            &lock(&self.conn),
            &format!("{LINKS} ORDER BY buds.path, links.position"),
            [],
        )?;
        Ok(found.into_iter().filter(|l| l.to.is_none()).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::parse;

    fn targets(body: &str) -> Vec<(String, Option<String>)> {
        parse(body).into_iter().map(|(t, l, _)| (t, l)).collect()
    }

    #[test]
    fn reads_targets_labels_and_headings() {
        assert_eq!(
            targets("See [[Plan]] and [[Launch/Welcome list|the list]], [[Notes#Week 2]]."),
            vec![
                ("Plan".into(), None),
                ("Launch/Welcome list".into(), Some("the list".into())),
                ("Notes".into(), None),
            ]
        );
    }

    #[test]
    fn code_holds_no_links() {
        let body = "`[[Not this]]` but [[This]]\n```\n[[Nor this]]\n```\n~~~\n[[Or this]]\n~~~\n[[After]]\n";
        assert_eq!(
            targets(body),
            vec![("This".into(), None), ("After".into(), None)]
        );
    }

    #[test]
    fn broken_and_empty_brackets_are_not_links() {
        assert_eq!(
            targets("[[]] [[ ]] [[open\nclose]] [[a [b] c]] [[#only heading]]"),
            vec![]
        );
    }

    #[test]
    fn offsets_point_at_the_brackets() {
        let body = "one\ntwo [[X]]";
        assert_eq!(parse(body)[0].2, body.find("[[").unwrap());
    }
}

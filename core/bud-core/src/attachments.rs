//! The pictures in the vault: every file with a picture's extension, found by the scan and kept
//! in the index by its path, with its size and modification time. The index only reads them
//! (ADR-001): nothing here writes a file, and where a new picture goes is not decided yet.
//!
//! Which buds show a picture is a question for the link index: an embed is a link of kind
//! `embed`, resolved to an attachment when it is read (links module).

use crate::{lock, Result, Vault};
use rusqlite::{params, Connection, OptionalExtension, Row as SqlRow};
use std::collections::{HashMap, HashSet};

/// One picture file as the folder has it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attachment {
    /// Relative to the vault root, `/`-separated.
    pub path: String,
    /// The file name alone, as an embed names it.
    pub name: String,
    pub size: u64,
    pub mtime: i64,
}

/// What a sync of the rows under a prefix did, by path.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct Synced {
    pub added: Vec<String>,
    pub updated: Vec<String>,
    pub removed: Vec<String>,
}

impl Synced {
    /// Every path whose row changed, in one list.
    pub fn changed(self) -> Vec<String> {
        let mut all = self.added;
        all.extend(self.updated);
        all.extend(self.removed);
        all
    }
}

/// Bring the rows at `prefix` and below it in step with `pictures`, what a walk of that prefix
/// found: a picture whose size and modification time the index knows is left alone, any other
/// is written, and a row no picture answers for is removed. An empty prefix is the whole vault;
/// a file's own path is a prefix of just that row.
pub(crate) fn sync(conn: &Connection, prefix: &str, pictures: &[Attachment]) -> Result<Synced> {
    let known: HashMap<String, (i64, i64)> = {
        let mut stmt = conn.prepare_cached(
            "SELECT path, size, mtime FROM attachments
             WHERE ?1 = '' OR path = ?1 OR substr(path, 1, length(?1) + 1) = ?1 || '/'",
        )?;
        let rows = stmt.query_map(params![prefix], |row| {
            Ok((row.get(0)?, (row.get(1)?, row.get(2)?)))
        })?;
        rows.collect::<std::result::Result<_, _>>()?
    };
    let mut synced = Synced::default();
    let mut seen = HashSet::with_capacity(pictures.len());
    for picture in pictures {
        seen.insert(picture.path.as_str());
        match known.get(&picture.path) {
            Some(&(size, mtime)) if size == picture.size as i64 && mtime == picture.mtime => {
                continue
            }
            Some(_) => synced.updated.push(picture.path.clone()),
            None => synced.added.push(picture.path.clone()),
        }
        conn.execute(
            "INSERT INTO attachments (path, name, size, mtime) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(path) DO UPDATE SET
                name = excluded.name, size = excluded.size, mtime = excluded.mtime",
            params![
                picture.path,
                picture.name,
                picture.size as i64,
                picture.mtime
            ],
        )?;
    }
    for path in known.keys() {
        if !seen.contains(path.as_str()) {
            conn.execute("DELETE FROM attachments WHERE path = ?1", params![path])?;
            synced.removed.push(path.clone());
        }
    }
    Ok(synced)
}

/// Delete the row at `rel` and every row below it; return the paths deleted.
pub(crate) fn remove_under(conn: &Connection, rel: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "DELETE FROM attachments WHERE path = ?1 OR substr(path, 1, length(?1) + 1) = ?1 || '/'
         RETURNING path",
    )?;
    let removed = stmt
        .query_map(params![rel], |row| row.get(0))?
        .collect::<std::result::Result<_, _>>()?;
    Ok(removed)
}

/// Move the rows under the folder `old` to the folder `new`, after the folder moved. A row left
/// behind at a new path, by an index that fell out of step, gives way.
pub(crate) fn relocate(conn: &Connection, old: &str, new: &str) -> Result<()> {
    conn.execute(
        "UPDATE OR REPLACE attachments SET path = ?2 || substr(path, length(?1) + 1)
         WHERE substr(path, 1, length(?1) + 1) = ?1 || '/'",
        params![old, new],
    )?;
    Ok(())
}

pub(crate) const SELECT: &str = "SELECT path, name, size, mtime FROM attachments";

pub(crate) fn read_attachment(row: &SqlRow<'_>) -> rusqlite::Result<Attachment> {
    let size: i64 = row.get(2)?;
    Ok(Attachment {
        path: row.get(0)?,
        name: row.get(1)?,
        size: u64::try_from(size).unwrap_or(0),
        mtime: row.get(3)?,
    })
}

impl Vault {
    /// Every picture in the index, by path; the Trash included, under `.trash/`.
    pub fn attachments(&self) -> Result<Vec<Attachment>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(&format!("{SELECT} ORDER BY path"))?;
        let rows = stmt.query_map([], read_attachment)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// One picture by its path.
    pub fn attachment(&self, path: &str) -> Result<Option<Attachment>> {
        let found = lock(&self.conn)
            .query_row(
                &format!("{SELECT} WHERE path = ?1"),
                params![path],
                read_attachment,
            )
            .optional()?;
        Ok(found)
    }
}

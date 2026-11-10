//! The pictures in the vault: every file with a picture's extension, found by the scan and kept
//! in the index by its path, with its size and modification time. The index only reads them
//! (ADR-001): nothing here writes a file, and where a new picture goes is not decided yet.
//!
//! Which buds show a picture is a question for the link index: an embed is a link of kind
//! `embed`, resolved to an attachment when it is read (links module).

use crate::{lock, scan, Result, Vault};
use rusqlite::{params, Connection, OptionalExtension, Row as SqlRow};

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

/// Write the row of a picture the scan found.
pub(crate) fn index(conn: &Connection, picture: &scan::Picture) -> Result<()> {
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
    Ok(())
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

/// Move the rows under the folder `old` to the folder `new`, after the folder moved.
pub(crate) fn relocate(conn: &Connection, old: &str, new: &str) -> Result<()> {
    conn.execute(
        "UPDATE attachments SET path = ?2 || substr(path, length(?1) + 1)
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

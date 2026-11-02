//! bud-core: a vault is a folder of Markdown files; SQLite is the index that follows it.
//!
//! The files are the only truth (ADR-001). This crate opens a vault folder, walks it into an
//! index kept outside the vault, and answers the queries the views need. Nothing here writes
//! into the vault until a later version adds the write operations.

mod frontmatter;
mod scan;

pub use frontmatter::{parse as parse_frontmatter, split as split_frontmatter, Properties};

use rusqlite::{params, Connection, OptionalExtension, Row};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

const SCHEMA: &str = include_str!("schema.sql");
const SCHEMA_VERSION: i64 = 1;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("sqlite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("not a folder: {0}")]
    NotAFolder(PathBuf),
}

pub type Result<T> = std::result::Result<T, Error>;

/// A bud with `state` is a to-do; without it, a note (ADR-002 §3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Note,
    Todo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Open,
    Done,
}

/// Where a bud lives: the tree of threads, or one of the reserved folders (ADR-002 §7).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Place {
    Everything,
    Inbox,
    Archive,
    Trash,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Note => "note",
            Kind::Todo => "todo",
        }
    }

    pub fn parse(text: &str) -> Option<Kind> {
        match text {
            "note" => Some(Kind::Note),
            "todo" => Some(Kind::Todo),
            _ => None,
        }
    }
}

impl State {
    pub fn as_str(self) -> &'static str {
        match self {
            State::Open => "open",
            State::Done => "done",
        }
    }

    pub fn parse(text: &str) -> Option<State> {
        match text {
            "open" => Some(State::Open),
            "done" => Some(State::Done),
            _ => None,
        }
    }
}

impl Place {
    pub fn as_str(self) -> &'static str {
        match self {
            Place::Everything => "everything",
            Place::Inbox => "inbox",
            Place::Archive => "archive",
            Place::Trash => "trash",
        }
    }

    pub fn parse(text: &str) -> Option<Place> {
        match text {
            "everything" => Some(Place::Everything),
            "inbox" => Some(Place::Inbox),
            "archive" => Some(Place::Archive),
            "trash" => Some(Place::Trash),
            _ => None,
        }
    }
}

/// One row of the index: a bud as the folder has it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bud {
    /// Relative to the vault root, `/`-separated: `Thread/Name.md` for a file, `Thread/Name` for
    /// a folder with no file of its own.
    pub path: String,
    /// The parent bud's path; none at the root of a place.
    pub parent: Option<String>,
    pub title: String,
    pub kind: Kind,
    pub state: Option<State>,
    pub when: Option<String>,
    pub due: Option<String>,
    pub pinned: bool,
    pub created: Option<String>,
    pub source: Option<String>,
    pub body: String,
    pub mtime: i64,
    pub place: Place,
}

impl Bud {
    pub fn is_todo(&self) -> bool {
        self.kind == Kind::Todo
    }

    pub fn is_done(&self) -> bool {
        self.state == Some(State::Done)
    }
}

/// What a rescan did.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ScanReport {
    pub added: usize,
    pub updated: usize,
    pub removed: usize,
}

impl ScanReport {
    pub fn is_unchanged(&self) -> bool {
        self.added == 0 && self.updated == 0 && self.removed == 0
    }
}

/// A folder of Markdown files and the index that follows it.
pub struct Vault {
    root: PathBuf,
    conn: Connection,
}

impl Vault {
    /// Open the vault at `vault_dir` with its index at `index_path`. The index file is created when
    /// missing and rebuilt when its schema is older than this crate's. Nothing in the vault is
    /// touched. Call [`Vault::rescan`] to fill the index.
    pub fn open(vault_dir: impl AsRef<Path>, index_path: impl AsRef<Path>) -> Result<Vault> {
        let root = vault_dir.as_ref().to_path_buf();
        if !root.is_dir() {
            return Err(Error::NotAFolder(root));
        }
        let conn = Connection::open(index_path.as_ref())?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        let version: i64 = conn.pragma_query_value(None, "user_version", |row| row.get(0))?;
        if version != SCHEMA_VERSION {
            conn.execute_batch("DROP TABLE IF EXISTS buds;")?;
        }
        conn.execute_batch(SCHEMA)?;
        conn.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        Ok(Vault { root, conn })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Walk the folder and bring the index up to date. Files whose modification time did not
    /// change since the last scan are not read again. Rows for files that are gone are removed.
    pub fn rescan(&mut self) -> Result<ScanReport> {
        let found = scan::walk(&self.root)?;
        let known: HashMap<String, (i64, Option<String>)> = {
            let mut stmt = self.conn.prepare("SELECT path, mtime, parent FROM buds")?;
            let rows = stmt.query_map([], |row| Ok((row.get(0)?, (row.get(1)?, row.get(2)?))))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        let mut report = ScanReport::default();
        let tx = self.conn.transaction()?;
        let mut seen = std::collections::HashSet::with_capacity(found.len());
        for item in &found {
            seen.insert(item.path.clone());
            match known.get(&item.path) {
                Some((mtime, parent)) if *mtime == item.mtime && *parent == item.parent => continue,
                Some(_) => report.updated += 1,
                None => report.added += 1,
            }
            let (props, body) = if item.is_folder {
                (Properties::default(), String::new())
            } else {
                let text = std::fs::read_to_string(&item.absolute)?;
                let (yaml, body) = frontmatter::split(&text);
                (
                    yaml.map(frontmatter::parse).unwrap_or_default(),
                    body.to_string(),
                )
            };
            let kind = if props.state.is_some() {
                Kind::Todo
            } else {
                Kind::Note
            };
            tx.execute(
                "INSERT OR REPLACE INTO buds
                 (path, parent, title, kind, state, when_date, due, pinned, created, source, body, mtime, place)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
                params![
                    item.path,
                    item.parent,
                    item.title,
                    kind.as_str(),
                    props.state.map(State::as_str),
                    props.when,
                    props.due,
                    props.pinned as i64,
                    props.created,
                    props.source,
                    body,
                    item.mtime,
                    item.place.as_str(),
                ],
            )?;
        }
        for path in known.keys() {
            if !seen.contains(path) {
                tx.execute("DELETE FROM buds WHERE path = ?1", params![path])?;
                report.removed += 1;
            }
        }
        tx.commit()?;
        Ok(report)
    }

    /// One bud by its path.
    pub fn bud(&self, path: &str) -> Result<Option<Bud>> {
        let bud = self
            .conn
            .query_row(
                &format!("{SELECT} WHERE path = ?1"),
                params![path],
                read_bud,
            )
            .optional()?;
        Ok(bud)
    }

    /// The direct children of a bud, by `created` then title.
    pub fn children(&self, path: &str) -> Result<Vec<Bud>> {
        self.query(
            &format!("{SELECT} WHERE parent = ?1 {ORDER}"),
            params![path],
        )
    }

    /// The buds at the top of a place: the threads of Everything, the captures in the Inbox.
    pub fn roots(&self, place: Place) -> Result<Vec<Bud>> {
        self.query(
            &format!("{SELECT} WHERE parent IS NULL AND place = ?1 {ORDER}"),
            params![place.as_str()],
        )
    }

    /// Every bud in the index, parents before children.
    pub fn all(&self) -> Result<Vec<Bud>> {
        self.query(&format!("{SELECT} ORDER BY length(path), path"), [])
    }

    fn query(&self, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Bud>> {
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map(args, read_bud)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }
}

const SELECT: &str = "SELECT path, parent, title, kind, state, when_date, due, pinned, created, source, body, mtime, place FROM buds";
const ORDER: &str = "ORDER BY created IS NULL, created, title COLLATE NOCASE";

fn read_bud(row: &Row<'_>) -> rusqlite::Result<Bud> {
    let kind: String = row.get(3)?;
    let state: Option<String> = row.get(4)?;
    let place: String = row.get(12)?;
    let pinned: i64 = row.get(7)?;
    Ok(Bud {
        path: row.get(0)?,
        parent: row.get(1)?,
        title: row.get(2)?,
        kind: Kind::parse(&kind).unwrap_or(Kind::Note),
        state: state.as_deref().and_then(State::parse),
        when: row.get(5)?,
        due: row.get(6)?,
        pinned: pinned != 0,
        created: row.get(8)?,
        source: row.get(9)?,
        body: row.get(10)?,
        mtime: row.get(11)?,
        place: Place::parse(&place).unwrap_or(Place::Everything),
    })
}

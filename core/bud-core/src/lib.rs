//! bud-core: a vault is a folder of Markdown files; SQLite is the index that follows it.
//!
//! The files are the only truth (ADR-001). This crate opens a vault folder, walks it into an
//! index kept outside the vault, and answers the queries the views need. The only write into the
//! vault are the edits in [`Vault::create`], [`Vault::set_body`], [`Vault::set_properties`],
//! [`Vault::rename`], [`Vault::move_to`], [`Vault::trash`] and [`Vault::restore`]: each changes
//! the file first and the index row after.

mod edit;
mod frontmatter;
mod links;
mod peer;
mod prose;
mod query;
mod scan;
mod sync;
mod tags;
mod watch;
mod words;

pub use edit::sanitize_filename;
pub use frontmatter::{
    layout as frontmatter_layout, parse as parse_frontmatter, split as split_frontmatter,
    write as write_frontmatter, write_layout as write_frontmatter_layout, Layout, Properties,
};

use rusqlite::{params, Connection, OptionalExtension, Row as SqlRow};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

pub use links::Link;
pub use peer::{
    Identity, JoinRequest, Node, NodeEvent, NodeListener, NodeOptions, NodeState, PeerInfo, Qr,
    Relay, RotateReport, RotationOutcome, Ticket,
};
pub use query::{Counts, Hit, Lens, Row};
pub use sync::{Heads, SyncReport, Updates};
pub use tags::{TagCount, TagEdit, TagOrigin};
pub use watch::{VaultListener, Watch};

const SCHEMA: &str = include_str!("schema.sql");
const SCHEMA_VERSION: i64 = 6;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("sqlite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("not a folder: {0}")]
    NotAFolder(PathBuf),
    #[error("no such bud: {0}")]
    NoSuchBud(String),
    #[error("already exists: {0}")]
    Exists(String),
    #[error("not allowed: {0}")]
    Invalid(String),
    #[error("watch: {0}")]
    Watch(String),
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
    /// Where a planted bud came from, as in `mail:M1234`; none for a bud made here.
    pub from: Option<String>,
    pub body: String,
    pub mtime: i64,
    pub place: Place,
    /// The tags of its frontmatter list, in order; the `#tags` in its body are not here.
    pub tags: Vec<String>,
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
    /// The folder of the index: what belongs to this machine and not to the vault lives here.
    index_dir: PathBuf,
    /// Behind a mutex because the watcher thread writes to the index too.
    conn: Arc<Mutex<Connection>>,
    /// The modification time of each file this vault wrote, so the watcher can skip its echo.
    written: Arc<Mutex<HashMap<String, i64>>>,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
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
            // Issued tickets are short-lived, so an older shape of their table is dropped too.
            conn.execute_batch(
                "DROP TABLE IF EXISTS buds; DROP TABLE IF EXISTS buds_fts; DROP TABLE IF EXISTS links; DROP TABLE IF EXISTS bud_tags;
                 DROP TABLE IF EXISTS tickets_issued;",
            )?;
        }
        conn.execute_batch(SCHEMA)?;
        conn.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        let index_dir = match index_path.as_ref().parent() {
            Some(dir) if !dir.as_os_str().is_empty() => dir.to_path_buf(),
            _ => PathBuf::from("."),
        };
        Ok(Vault {
            root,
            index_dir,
            conn: Arc::new(Mutex::new(conn)),
            written: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// Follow the folder: watch it for changes made by other programs, reindex the paths each
    /// batch touched, and tell `listener` once per batch. Watching stops when the returned
    /// [`Watch`] is dropped.
    pub fn watch(&self, listener: Box<dyn VaultListener>) -> Result<Watch> {
        watch::start(
            self.root.clone(),
            Arc::clone(&self.conn),
            Arc::clone(&self.written),
            listener,
        )
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Walk the folder and bring the index up to date. Files whose modification time did not
    /// change since the last scan are not read again. Rows for files that are gone are removed.
    pub fn rescan(&mut self) -> Result<ScanReport> {
        let found = scan::walk(&self.root)?;
        let mut conn = lock(&self.conn);
        let known: HashMap<String, (i64, Option<String>)> = {
            let mut stmt = conn.prepare("SELECT path, mtime, parent FROM buds")?;
            let rows = stmt.query_map([], |row| Ok((row.get(0)?, (row.get(1)?, row.get(2)?))))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        let mut report = ScanReport::default();
        let tx = conn.transaction()?;
        let mut seen = std::collections::HashSet::with_capacity(found.len());
        for item in &found {
            seen.insert(item.path.clone());
            match known.get(&item.path) {
                Some((mtime, parent)) if *mtime == item.mtime && *parent == item.parent => continue,
                Some(_) => report.updated += 1,
                None => report.added += 1,
            }
            index_found(&tx, item)?;
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

    /// Set the known frontmatter keys of a bud to `props`: a key that is none is removed. Nothing
    /// else in the file changes. The file is written to `<name>.md.tmp` beside it and renamed into
    /// place, and the index row follows. A bud that is only a folder gets `Name.md` beside the
    /// folder first, and its children now belong to that file.
    pub fn set_properties(&mut self, path: &str, props: &Properties) -> Result<()> {
        self.write_properties(path, props, None)
    }

    /// [`Vault::set_properties`], and with a layout the unknown keys of the block follow it too.
    pub(crate) fn write_properties(
        &mut self,
        path: &str,
        props: &Properties,
        layout: Option<&Layout>,
    ) -> Result<()> {
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        let text = if path.ends_with(".md") {
            std::fs::read_to_string(self.root.join(path))?
        } else {
            String::new()
        };
        let mut written = frontmatter::write(&text, props);
        if let Some(layout) = layout {
            written = frontmatter::write_layout(&written, layout);
        }
        self.write_file(path, &written, Some(props))
    }

    /// Write the whole text of the bud at `path` and let its row follow: its properties (`props`,
    /// or what the text says), links and tags. A bud that is only a folder gets `Name.md` beside
    /// the folder, and its children now belong to that file.
    pub(crate) fn write_file(
        &mut self,
        path: &str,
        written: &str,
        props: Option<&Properties>,
    ) -> Result<()> {
        let bud = self
            .bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        let is_folder = !path.ends_with(".md");
        let file_path = if is_folder {
            format!("{path}.md")
        } else {
            path.to_string()
        };
        let absolute = self.root.join(&file_path);
        edit::write_atomic(&absolute, written)?;
        let mtime = edit::mtime_of(&absolute);
        let (yaml, body) = frontmatter::split(written);
        let read = yaml.map(frontmatter::parse).unwrap_or_default();
        let props = props.unwrap_or(&read);
        let row = Placement {
            path: &file_path,
            parent: bud.parent.as_deref(),
            title: &bud.title,
            place: bud.place,
            mtime,
        };
        lock(&self.written).insert(file_path.clone(), mtime);
        let mut conn = lock(&self.conn);
        let tx = conn.transaction()?;
        if is_folder {
            tx.execute("DELETE FROM buds WHERE path = ?1", params![path])?;
            tx.execute(
                "UPDATE buds SET parent = ?1 WHERE parent = ?2",
                params![file_path, path],
            )?;
            // The bud's sync document moves with it, so a sync sees the same bud at its file
            // and not a folder gone and a new bud come.
            tx.execute(
                "UPDATE docs SET path = ?1 WHERE path = ?2",
                params![file_path, path],
            )?;
        }
        insert_row(&tx, &row, props, yaml, body)?;
        tx.commit()?;
        Ok(())
    }

    /// One bud by its path.
    pub fn bud(&self, path: &str) -> Result<Option<Bud>> {
        let bud = lock(&self.conn)
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

    /// How many buds the index holds, the Trash included.
    pub fn bud_count(&self) -> Result<usize> {
        let count: i64 =
            lock(&self.conn).query_row("SELECT COUNT(*) FROM buds", [], |r| r.get(0))?;
        Ok(usize::try_from(count).unwrap_or(0))
    }

    /// Every bud in the index, parents before children.
    pub fn all(&self) -> Result<Vec<Bud>> {
        self.query(&format!("{SELECT} ORDER BY length(path), path"), [])
    }

    fn query(&self, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Bud>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(sql)?;
        let rows = stmt.query_map(args, read_bud)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }
}

/// Read the file behind `item` (a folder has none) and write its row.
fn index_found(conn: &Connection, item: &scan::Found) -> Result<()> {
    let text = if item.is_folder {
        String::new()
    } else {
        std::fs::read_to_string(&item.absolute)?
    };
    let (yaml, body) = frontmatter::split(&text);
    let props = yaml.map(frontmatter::parse).unwrap_or_default();
    let row = Placement {
        path: &item.path,
        parent: item.parent.as_deref(),
        title: &item.title,
        place: item.place,
        mtime: item.mtime,
    };
    insert_row(conn, &row, &props, yaml, body)
}

/// The parts of a row that come from the folder rather than from the file's frontmatter.
struct Placement<'a> {
    path: &'a str,
    parent: Option<&'a str>,
    title: &'a str,
    place: Place,
    mtime: i64,
}

fn insert_row(
    conn: &Connection,
    row: &Placement<'_>,
    props: &Properties,
    yaml: Option<&str>,
    body: &str,
) -> Result<()> {
    let kind = if props.state.is_some() {
        Kind::Todo
    } else {
        Kind::Note
    };
    // An upsert and not a replace: the row keeps its rowid, which the search index follows.
    conn.execute(
        "INSERT INTO buds
         (path, parent, title, kind, state, when_date, due, pinned, created, source, body, mtime, place,
          planted_from)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
         ON CONFLICT(path) DO UPDATE SET
            parent = excluded.parent, title = excluded.title, kind = excluded.kind,
            state = excluded.state, when_date = excluded.when_date, due = excluded.due,
            pinned = excluded.pinned, created = excluded.created, source = excluded.source,
            body = excluded.body, mtime = excluded.mtime, place = excluded.place,
            planted_from = excluded.planted_from",
        params![
            row.path,
            row.parent,
            row.title,
            kind.as_str(),
            props.state.map(State::as_str),
            props.when,
            props.due,
            props.pinned as i64,
            props.created,
            props.source,
            body,
            row.mtime,
            row.place.as_str(),
            props.from,
        ],
    )?;
    links::relink(conn, row.path, body)?;
    tags::retag(conn, row.path, yaml, body)
}

pub(crate) const SELECT: &str = "SELECT path, parent, title, kind, state, when_date, due, pinned, created, source, body, mtime, place,
    (SELECT group_concat(tag, char(31) ORDER BY position) FROM bud_tags
     WHERE bud_tags.source = buds.rowid AND origin = 'frontmatter'), planted_from FROM buds";
const ORDER: &str = "ORDER BY created IS NULL, created, title COLLATE NOCASE";

pub(crate) fn read_bud(row: &SqlRow<'_>) -> rusqlite::Result<Bud> {
    let kind: String = row.get(3)?;
    let state: Option<String> = row.get(4)?;
    let place: String = row.get(12)?;
    let pinned: i64 = row.get(7)?;
    let tags: Option<String> = row.get(13)?;
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
        from: row.get(14)?,
        body: row.get(10)?,
        mtime: row.get(11)?,
        place: Place::parse(&place).unwrap_or(Place::Everything),
        tags: tags.map_or_else(Vec::new, |t| {
            t.split('\u{1f}').map(str::to_string).collect()
        }),
    })
}

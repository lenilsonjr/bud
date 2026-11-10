//! Follow the vault folder: a `notify` watcher feeds a thread that debounces events, reindexes
//! only the paths a batch touched, and tells the listener once per batch (ADR-001 §4).

use crate::{attachments, index_found, lock, scan, Error, Result};
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use rusqlite::{params, Connection};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

/// How long the folder must be quiet before a batch is handled.
const DEBOUNCE: Duration = Duration::from_millis(300);
/// A folder that never goes quiet is still handled this often.
const LONGEST_BATCH: Duration = Duration::from_secs(2);
/// How often the thread looks at whether it was told to stop.
const STOP_CHECK: Duration = Duration::from_millis(100);

/// Told once per batch of changes, after the index has followed them. One method, so it can be
/// exported as a callback interface.
pub trait VaultListener: Send + Sync + 'static {
    /// `paths` are relative to the vault root and `/`-separated: the files whose rows were
    /// added, changed or removed.
    fn changed(&self, paths: Vec<String>);
}

/// A running watcher. Dropping it stops the watcher and its thread.
pub struct Watch {
    watcher: Option<RecommendedWatcher>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Drop for Watch {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        drop(self.watcher.take());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

type Written = Arc<Mutex<HashMap<String, i64>>>;

struct Context {
    root: PathBuf,
    canonical_root: PathBuf,
    conn: Arc<Mutex<Connection>>,
    written: Written,
    listener: Box<dyn VaultListener>,
}

pub fn start(
    root: PathBuf,
    conn: Arc<Mutex<Connection>>,
    written: Written,
    listener: Box<dyn VaultListener>,
) -> Result<Watch> {
    let (tx, rx) = channel();
    let mut watcher = notify::recommended_watcher(move |event| {
        let _ = tx.send(event);
    })?;
    watcher.watch(&root, RecursiveMode::Recursive)?;
    let stop = Arc::new(AtomicBool::new(false));
    let context = Context {
        canonical_root: std::fs::canonicalize(&root).unwrap_or_else(|_| root.clone()),
        root,
        conn,
        written,
        listener,
    };
    let thread = {
        let stop = Arc::clone(&stop);
        std::thread::spawn(move || run(rx, &context, &stop))
    };
    Ok(Watch {
        watcher: Some(watcher),
        stop,
        thread: Some(thread),
    })
}

type Incoming = notify::Result<notify::Event>;

fn run(rx: Receiver<Incoming>, context: &Context, stop: &AtomicBool) {
    loop {
        let first = loop {
            if stop.load(Ordering::SeqCst) {
                return;
            }
            match rx.recv_timeout(STOP_CHECK) {
                Ok(event) => break event,
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }
        };
        let mut events = vec![first];
        let deadline = Instant::now() + LONGEST_BATCH;
        loop {
            let wait = DEBOUNCE.min(deadline.saturating_duration_since(Instant::now()));
            if wait.is_zero() {
                break;
            }
            match rx.recv_timeout(wait) {
                Ok(event) => events.push(event),
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
        if stop.load(Ordering::SeqCst) {
            return;
        }
        let touched = touched_paths(events);
        if touched.is_empty() {
            continue;
        }
        let changed = reindex(context, &touched);
        if !changed.is_empty() {
            context.listener.changed(changed);
        }
    }
}

/// The absolute paths a batch of events names, each once. Events that cannot be read are logged.
fn touched_paths(events: Vec<Incoming>) -> BTreeSet<PathBuf> {
    let mut touched = BTreeSet::new();
    for event in events {
        match event {
            Ok(event) => {
                if matches!(event.kind, EventKind::Access(_)) {
                    continue;
                }
                touched.extend(event.paths);
            }
            Err(err) => eprintln!("bud-core: watcher event skipped: {err}"),
        }
    }
    touched
}

/// Bring the index up to date for `touched` and return the paths whose rows changed.
fn reindex(context: &Context, touched: &BTreeSet<PathBuf>) -> Vec<String> {
    let mut changed = BTreeSet::new();
    let mut conn = lock(&context.conn);
    let tx = match conn.transaction() {
        Ok(tx) => tx,
        Err(err) => {
            eprintln!("bud-core: watcher could not open a transaction: {err}");
            return Vec::new();
        }
    };
    for absolute in touched {
        let Some(relative) = relative_to_root(context, absolute) else {
            continue;
        };
        if relative.as_os_str().is_empty() || scan::is_ignored(&relative) {
            continue;
        }
        if let Err(err) = reindex_path(context, &tx, &relative, &mut changed) {
            eprintln!(
                "bud-core: watcher skipped {}: {err}",
                scan::relative_string(&relative)
            );
        }
    }
    if let Err(err) = tx.commit() {
        eprintln!("bud-core: watcher could not save the index: {err}");
        return Vec::new();
    }
    changed.into_iter().collect()
}

fn relative_to_root(context: &Context, absolute: &Path) -> Option<PathBuf> {
    absolute
        .strip_prefix(&context.root)
        .or_else(|_| absolute.strip_prefix(&context.canonical_root))
        .ok()
        .map(Path::to_path_buf)
}

fn reindex_path(
    context: &Context,
    tx: &Connection,
    relative: &Path,
    changed: &mut BTreeSet<String>,
) -> Result<()> {
    let rel = scan::relative_string(relative);
    let absolute = context.root.join(relative);
    match std::fs::symlink_metadata(&absolute) {
        Ok(meta) if meta.is_dir() => {
            sync_dir(tx, &context.root, relative, changed)?;
        }
        Ok(meta) if meta.is_file() => {
            if scan::is_picture(&rel) {
                if let Some(picture) = scan::probe_picture(&context.root, relative) {
                    attachments::index(tx, &picture)?;
                    changed.insert(rel.clone());
                }
                return Ok(());
            }
            if !rel.ends_with(".md") {
                return Ok(());
            }
            let Some(found) = scan::probe(&context.root, relative) else {
                return Ok(());
            };
            if lock(&context.written).get(&rel) == Some(&found.mtime) {
                return Ok(());
            }
            index_found(tx, &found)?;
            changed.insert(rel.clone());
        }
        Ok(_) => return Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let removed = remove_under(tx, &rel)?;
            if rel.ends_with(".md") || scan::is_picture(&rel) {
                // Only a file's row changes the report; a folder's rows are listed by their own.
                if removed.contains(&rel) {
                    changed.insert(rel.clone());
                }
            } else {
                changed.extend(removed);
            }
        }
        Err(err) => return Err(err.into()),
    }
    reconcile_folder(tx, &context.root, &rel)
}

/// Index a folder that exists, and everything below it that moved or changed.
fn sync_dir(
    tx: &Connection,
    root: &Path,
    relative: &Path,
    changed: &mut BTreeSet<String>,
) -> Result<()> {
    let rel = scan::relative_string(relative);
    let found = scan::walk_under(root, relative)?;
    let mut seen = HashSet::with_capacity(found.buds.len());
    for item in &found.buds {
        seen.insert(item.path.clone());
        let known: Option<(i64, Option<String>)> = tx
            .query_row(
                "SELECT mtime, parent FROM buds WHERE path = ?1",
                params![item.path],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .ok();
        if matches!(&known, Some((mtime, parent)) if *mtime == item.mtime && *parent == item.parent)
        {
            continue;
        }
        match index_found(tx, item) {
            Ok(()) => {
                changed.insert(item.path.clone());
            }
            Err(err) => eprintln!("bud-core: watcher skipped {}: {err}", item.path),
        }
    }
    let mut stmt = tx.prepare(
        "SELECT path FROM buds WHERE path = ?1 OR substr(path, 1, length(?1) + 1) = ?1 || '/'",
    )?;
    let indexed: Vec<String> = stmt
        .query_map(params![rel], |row| row.get(0))?
        .collect::<std::result::Result<_, _>>()?;
    drop(stmt);
    for path in indexed {
        if !seen.contains(&path) {
            tx.execute("DELETE FROM buds WHERE path = ?1", params![path])?;
            changed.insert(path);
        }
    }
    let mut seen = HashSet::with_capacity(found.pictures.len());
    for picture in &found.pictures {
        seen.insert(picture.path.clone());
        let known: Option<(i64, i64)> = tx
            .query_row(
                "SELECT size, mtime FROM attachments WHERE path = ?1",
                params![picture.path],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .ok();
        if known == Some((picture.size as i64, picture.mtime)) {
            continue;
        }
        attachments::index(tx, picture)?;
        changed.insert(picture.path.clone());
    }
    let mut stmt = tx.prepare(
        "SELECT path FROM attachments WHERE path = ?1 OR substr(path, 1, length(?1) + 1) = ?1 || '/'",
    )?;
    let indexed: Vec<String> = stmt
        .query_map(params![rel], |row| row.get(0))?
        .collect::<std::result::Result<_, _>>()?;
    drop(stmt);
    for path in indexed {
        if !seen.contains(&path) {
            tx.execute("DELETE FROM attachments WHERE path = ?1", params![path])?;
            changed.insert(path);
        }
    }
    Ok(())
}

/// Delete the rows at `rel` and every row below it, buds and attachments alike; return the paths
/// deleted.
fn remove_under(tx: &Connection, rel: &str) -> Result<Vec<String>> {
    let mut stmt = tx.prepare(
        "DELETE FROM buds WHERE path = ?1 OR substr(path, 1, length(?1) + 1) = ?1 || '/'
         RETURNING path",
    )?;
    let mut removed: Vec<String> = stmt
        .query_map(params![rel], |row| row.get(0))?
        .collect::<std::result::Result<_, _>>()?;
    drop(stmt);
    removed.extend(attachments::remove_under(tx, rel)?);
    Ok(removed)
}

/// `Name.md` and the folder `Name` are one bud: when either appears or goes, the folder's own row
/// and the parent of its children follow.
fn reconcile_folder(tx: &Connection, root: &Path, rel: &str) -> Result<()> {
    let stem = rel.strip_suffix(".md").unwrap_or(rel);
    let folder = Path::new(stem);
    if !root.join(folder).is_dir() || scan::is_ignored(folder) {
        return Ok(());
    }
    let file = format!("{stem}.md");
    let owner = if root.join(&file).is_file() {
        file.as_str()
    } else {
        stem
    };
    match scan::probe(root, folder) {
        Some(found) => index_found(tx, &found)?,
        None => {
            tx.execute("DELETE FROM buds WHERE path = ?1", params![stem])?;
        }
    }
    tx.execute(
        "UPDATE buds SET parent = ?1 WHERE parent IN (?2, ?3) AND parent != ?1",
        params![owner, stem, file],
    )?;
    Ok(())
}

impl From<notify::Error> for Error {
    fn from(err: notify::Error) -> Error {
        Error::Watch(err.to_string())
    }
}

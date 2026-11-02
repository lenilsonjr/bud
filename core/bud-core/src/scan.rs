//! Walk a vault folder and say which buds are in it, without reading any file body.
//!
//! The rules are ADR-002's: a Markdown file is a bud; a folder with the same name beside it holds
//! its children; a folder with no such file is a bud of its own; `Inbox/`, `Archive/` and
//! `.trash/` at the root are places, not buds; other dot folders and non-Markdown files are
//! skipped.

use crate::Place;
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;
use walkdir::WalkDir;

/// A bud the walk found, before its file is read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    /// Relative to the vault root, `/`-separated, with `.md` for a file and nothing for a folder.
    pub path: String,
    pub parent: Option<String>,
    pub title: String,
    pub place: Place,
    pub is_folder: bool,
    pub absolute: PathBuf,
    pub mtime: i64,
}

pub(crate) const RESERVED: [&str; 3] = ["Inbox", "Archive", ".trash"];

pub fn walk(root: &Path) -> std::io::Result<Vec<Found>> {
    walk_under(root, Path::new(""))
}

/// Walk `start`, a path relative to `root`, and everything below it. The start itself is
/// included when it is a bud. An empty `start` is the whole vault.
pub fn walk_under(root: &Path, start: &Path) -> std::io::Result<Vec<Found>> {
    let mut found = Vec::new();
    let base = start.components().count();
    let walker = WalkDir::new(root.join(start))
        .min_depth(if base == 0 { 1 } else { 0 })
        .follow_links(false)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|entry| {
            let name = entry.file_name().to_string_lossy();
            // Dot entries are skipped, except the trash at the root.
            !name.starts_with('.') || (entry.depth() + base == 1 && name == ".trash")
        });
    for entry in walker {
        let entry = entry?;
        let relative = entry.path().strip_prefix(root).unwrap_or(entry.path());
        let file_type = entry.file_type();
        let mtime = mtime_of(&entry.metadata()?);
        if let Some(item) = classify(
            root,
            relative,
            file_type.is_dir(),
            file_type.is_file(),
            mtime,
        ) {
            found.push(item);
        }
    }
    Ok(found)
}

/// What is at `relative` right now, by the same rules as the walk: none when it is missing,
/// ignored or not a bud.
pub fn probe(root: &Path, relative: &Path) -> Option<Found> {
    if is_ignored(relative) {
        return None;
    }
    let meta = std::fs::symlink_metadata(root.join(relative)).ok()?;
    let file_type = meta.file_type();
    classify(
        root,
        relative,
        file_type.is_dir(),
        file_type.is_file(),
        mtime_of(&meta),
    )
}

/// True for a path the scan never looks at: any dot entry, except `.trash` at the root.
pub fn is_ignored(relative: &Path) -> bool {
    relative.components().enumerate().any(|(i, c)| match c {
        Component::Normal(part) => {
            let name = part.to_string_lossy();
            name.starts_with('.') && !(i == 0 && name == ".trash")
        }
        _ => false,
    })
}

fn mtime_of(meta: &std::fs::Metadata) -> i64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn classify(
    root: &Path,
    relative: &Path,
    is_dir: bool,
    is_file: bool,
    mtime: i64,
) -> Option<Found> {
    let rel = relative_string(relative);
    let name = relative.file_name()?.to_string_lossy().to_string();
    let depth = relative.components().count();
    let absolute = root.join(relative);
    if is_dir {
        if depth == 1 && RESERVED.contains(&name.as_str()) {
            return None;
        }
        // A folder beside `Name.md` holds that bud's children and is not a bud itself.
        if sibling_file(root, relative).exists() {
            return None;
        }
        let parent = parent_bud(root, relative.parent().unwrap_or(Path::new("")));
        Some(Found {
            path: rel,
            parent,
            title: name,
            place: place_of(relative),
            is_folder: true,
            absolute,
            mtime,
        })
    } else if is_file {
        let title = name.strip_suffix(".md")?.to_string();
        let parent = parent_bud(root, relative.parent().unwrap_or(Path::new("")));
        Some(Found {
            path: rel,
            parent,
            title,
            place: place_of(relative),
            is_folder: false,
            absolute,
            mtime,
        })
    } else {
        None
    }
}

/// The bud that owns the entries of `dir`: `dir.md` when it exists, else the folder itself, and
/// none at the root or directly inside a place.
pub(crate) fn parent_bud(root: &Path, dir: &Path) -> Option<String> {
    if dir.as_os_str().is_empty() {
        return None;
    }
    if dir.components().count() == 1 && RESERVED.contains(&relative_string(dir).as_str()) {
        return None;
    }
    if sibling_file(root, dir).exists() {
        Some(format!("{}.md", relative_string(dir)))
    } else {
        Some(relative_string(dir))
    }
}

/// `a/b` → `root/a/b.md`.
pub(crate) fn sibling_file(root: &Path, dir: &Path) -> PathBuf {
    let mut file = root.join(dir).into_os_string();
    file.push(".md");
    PathBuf::from(file)
}

pub(crate) fn place_of(relative: &Path) -> Place {
    match relative.components().next() {
        Some(Component::Normal(first)) => match first.to_string_lossy().as_ref() {
            "Inbox" => Place::Inbox,
            "Archive" => Place::Archive,
            ".trash" => Place::Trash,
            _ => Place::Everything,
        },
        _ => Place::Everything,
    }
}

pub fn relative_string(path: &Path) -> String {
    path.components()
        .filter_map(|c| match c {
            Component::Normal(part) => Some(part.to_string_lossy().into_owned()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/")
}

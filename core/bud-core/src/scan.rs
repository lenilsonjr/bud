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
    let mut found = Vec::new();
    let walker = WalkDir::new(root)
        .min_depth(1)
        .follow_links(false)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|entry| {
            let name = entry.file_name().to_string_lossy();
            // Dot entries are skipped, except the trash at the root.
            !name.starts_with('.') || (entry.depth() == 1 && name == ".trash")
        });
    for entry in walker {
        let entry = entry?;
        let relative = entry.path().strip_prefix(root).unwrap_or(entry.path());
        let rel = relative_string(relative);
        let depth = entry.depth();
        let file_type = entry.file_type();
        let mtime = entry
            .metadata()?
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        if file_type.is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            if depth == 1 && RESERVED.contains(&name.as_str()) {
                continue;
            }
            // A folder beside `Name.md` holds that bud's children and is not a bud itself.
            if sibling_file(root, relative).exists() {
                continue;
            }
            let parent = parent_bud(root, relative.parent().unwrap_or(Path::new("")));
            found.push(Found {
                path: rel,
                parent,
                title: name,
                place: place_of(relative),
                is_folder: true,
                absolute: entry.path().to_path_buf(),
                mtime,
            });
        } else if file_type.is_file() {
            let name = entry.file_name().to_string_lossy();
            let Some(title) = name.strip_suffix(".md") else {
                continue;
            };
            let parent = parent_bud(root, relative.parent().unwrap_or(Path::new("")));
            found.push(Found {
                path: rel,
                parent,
                title: title.to_string(),
                place: place_of(relative),
                is_folder: false,
                absolute: entry.path().to_path_buf(),
                mtime,
            });
        }
    }
    Ok(found)
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

fn relative_string(path: &Path) -> String {
    path.components()
        .filter_map(|c| match c {
            Component::Normal(part) => Some(part.to_string_lossy().into_owned()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/")
}

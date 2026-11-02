//! Two replicas of one vault, each with its own index, that exchange documents as bytes.

#![allow(dead_code)]

use bud_core::Vault;
use pretty_assertions::assert_eq;
use std::collections::BTreeMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};

pub fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")
}

pub fn copy_dir(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_dir(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

pub fn fingerprint(root: &Path) -> BTreeMap<String, u64> {
    fn visit(root: &Path, dir: &Path, out: &mut BTreeMap<String, u64>) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let entry = entry.unwrap();
            if entry.file_type().unwrap().is_dir() {
                visit(root, &entry.path(), out);
            } else {
                let mut hasher = DefaultHasher::new();
                std::fs::read(entry.path()).unwrap().hash(&mut hasher);
                let path = entry.path();
                let rel = path.strip_prefix(root).unwrap().to_string_lossy();
                out.insert(rel.into_owned(), hasher.finish());
            }
        }
    }
    let mut out = BTreeMap::new();
    visit(root, root, &mut out);
    out
}

pub struct Replica {
    pub vault: Vault,
    pub dir: tempfile::TempDir,
    _index: tempfile::TempDir,
}

impl Replica {
    pub fn new() -> Replica {
        let dir = tempfile::tempdir().unwrap();
        copy_dir(&fixture(), dir.path());
        let index = tempfile::tempdir().unwrap();
        let mut vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
        vault.rescan().unwrap();
        Replica {
            vault,
            dir,
            _index: index,
        }
    }

    pub fn read(&self, name: &str) -> String {
        std::fs::read_to_string(self.dir.path().join(name)).unwrap()
    }

    pub fn exists(&self, name: &str) -> bool {
        self.dir.path().join(name).exists()
    }

    pub fn write(&self, name: &str, text: &str) {
        std::fs::write(self.dir.path().join(name), text).unwrap();
    }

    pub fn rescan_and_sync(&mut self) -> bud_core::SyncReport {
        self.vault.rescan().unwrap();
        self.vault.sync().unwrap()
    }
}

/// Two replicas of one vault that share the identities of every bud.
pub fn pair() -> (Replica, Replica) {
    let mut a = Replica::new();
    let mut b = Replica::new();
    a.vault.sync().unwrap();
    for bud in b.vault.all().unwrap() {
        if bud.place == bud_core::Place::Trash && !bud.path.ends_with(".md") {
            continue;
        }
        let id = a.vault.doc_id(&bud.path).unwrap().unwrap();
        let bytes = a.vault.doc_bytes(&bud.path).unwrap().unwrap();
        b.vault.adopt_doc(&bud.path, &id, &bytes).unwrap();
    }
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    let (a_sync, b_sync) = (a.vault.sync().unwrap(), b.vault.sync().unwrap());
    assert_eq!((a_sync.ops, b_sync.ops), (0, 0));
    (a, b)
}

pub fn send_doc(from: &Replica, to: &mut Replica, path_in_from: &str) -> bud_core::SyncReport {
    let id = from.vault.doc_id(path_in_from).unwrap().unwrap();
    let bytes = from.vault.doc_bytes(path_in_from).unwrap().unwrap();
    to.vault.merge_doc(&id, &bytes).unwrap()
}

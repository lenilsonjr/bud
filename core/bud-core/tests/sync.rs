//! The sync module: one document per bud, reconciled with the Markdown file. Two replicas are two
//! copies of the fixture vault, each with its own index; documents travel as bytes.

use bud_core::Vault;
use pretty_assertions::assert_eq;
use std::collections::BTreeMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")
}

fn copy_dir(from: &Path, to: &Path) {
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

fn fingerprint(root: &Path) -> BTreeMap<String, u64> {
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

struct Replica {
    vault: Vault,
    dir: tempfile::TempDir,
    _index: tempfile::TempDir,
}

impl Replica {
    fn new() -> Replica {
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

    fn read(&self, name: &str) -> String {
        std::fs::read_to_string(self.dir.path().join(name)).unwrap()
    }

    fn exists(&self, name: &str) -> bool {
        self.dir.path().join(name).exists()
    }

    fn write(&self, name: &str, text: &str) {
        std::fs::write(self.dir.path().join(name), text).unwrap();
    }

    fn rescan_and_sync(&mut self) -> bud_core::SyncReport {
        self.vault.rescan().unwrap();
        self.vault.sync().unwrap()
    }
}

/// Two replicas of one vault that share the identities of every bud.
fn pair() -> (Replica, Replica) {
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

fn send_doc(from: &Replica, to: &mut Replica, path_in_from: &str) -> bud_core::SyncReport {
    let id = from.vault.doc_id(path_in_from).unwrap().unwrap();
    let bytes = from.vault.doc_bytes(path_in_from).unwrap().unwrap();
    to.vault.merge_doc(&id, &bytes).unwrap()
}

#[test]
fn the_first_sync_makes_a_document_for_every_bud() {
    let mut replica = Replica::new();
    let report = replica.vault.sync().unwrap();
    assert_eq!(report.created, 13);
    assert_eq!(report.written, 0);
    for bud in replica.vault.all().unwrap() {
        assert!(
            replica.vault.doc_id(&bud.path).unwrap().is_some(),
            "{}",
            bud.path
        );
    }
    let text = replica.read("Gift ideas.md");
    let (_, body) = bud_core::split_frontmatter(&text);
    assert_eq!(
        replica.vault.doc_text("Gift ideas.md").unwrap().as_deref(),
        Some(body)
    );
    let again = replica.vault.sync().unwrap();
    assert_eq!(
        (again.created, again.updated, again.written, again.ops),
        (0, 0, 0, 0)
    );
}

#[test]
fn a_scan_and_a_sync_never_write_the_vault() {
    let before = fingerprint(&fixture());
    let index = tempfile::tempdir().unwrap();
    let mut vault = Vault::open(fixture(), index.path().join("index.db")).unwrap();
    vault.rescan().unwrap();
    vault.sync().unwrap();
    vault.rescan().unwrap();
    vault.sync().unwrap();
    assert_eq!(fingerprint(&fixture()), before);
}

#[test]
fn an_outside_edit_becomes_operations_and_no_file_write() {
    let mut replica = Replica::new();
    replica.vault.sync().unwrap();
    let edited = "---\nstate: done\ndue: 2026-11-09\n---\nWarm, not corporate.\nAnd brief.\n";
    replica.write("Launch the newsletter/Design notes.md", edited);
    let mtime = std::fs::metadata(
        replica
            .dir
            .path()
            .join("Launch the newsletter/Design notes.md"),
    )
    .unwrap()
    .modified()
    .unwrap();
    let report = replica.rescan_and_sync();
    assert_eq!(report.updated, 1);
    assert!(report.ops > 0);
    assert_eq!(report.written, 0);
    assert_eq!(
        replica.read("Launch the newsletter/Design notes.md"),
        edited
    );
    assert_eq!(
        std::fs::metadata(
            replica
                .dir
                .path()
                .join("Launch the newsletter/Design notes.md")
        )
        .unwrap()
        .modified()
        .unwrap(),
        mtime
    );
    assert_eq!(
        replica
            .vault
            .doc_text("Launch the newsletter/Design notes.md")
            .unwrap()
            .as_deref(),
        Some("Warm, not corporate.\nAnd brief.\n")
    );
    // Properties are map sets: the document now writes back what the file says, so nothing more.
    let again = replica.rescan_and_sync();
    assert_eq!((again.ops, again.written), (0, 0));
}

#[test]
fn two_documents_edited_apart_merge_to_one_text_with_both_edits() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Design notes.md";
    a.write(path, "## Voice\n\nWarm, not corporate.\nShort sentences.\n");
    b.write(path, "## Tone and voice\n\nWarm, not corporate.\n");
    a.rescan_and_sync();
    b.rescan_and_sync();

    let a_to_b = send_doc(&a, &mut b, path);
    assert_eq!(a_to_b.written, 1);
    let b_to_a = send_doc(&b, &mut a, path);
    assert_eq!(b_to_a.written, 1);

    let merged = "## Tone and voice\n\nWarm, not corporate.\nShort sentences.\n";
    assert_eq!(a.read(path), merged);
    assert_eq!(b.read(path), merged);

    // Merging what is already merged writes nothing.
    let again = send_doc(&a, &mut b, path);
    assert_eq!(again.written, 0);
    let again = send_doc(&b, &mut a, path);
    assert_eq!(again.written, 0);
}

#[test]
fn a_property_set_on_one_replica_reaches_the_file_of_the_other() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Set up the sender.md";
    let text = a.read(path);
    a.write(path, &text.replacen("state: open", "state: done", 1));
    a.rescan_and_sync();
    send_doc(&a, &mut b, path);
    assert!(b.read(path).contains("state: done"));
    // Only the key line changed.
    assert_eq!(b.read(path), a.read(path));
}

#[test]
fn a_rename_on_one_replica_and_an_edit_on_the_other_end_with_the_edit_under_the_new_name() {
    let (mut a, mut b) = pair();
    let old = "Gift ideas.md";
    let new = "Present ideas.md";
    let id = a.vault.doc_id(old).unwrap().unwrap();

    a.vault.rename(old, "Present ideas").unwrap();
    a.vault.sync().unwrap();

    let original = b.read(old);
    b.write(old, &format!("{original}A scarf.\n"));
    b.rescan_and_sync();

    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(!b.exists(old));
    assert_eq!(b.vault.doc_id(new).unwrap().as_deref(), Some(id.as_str()));
    send_doc(&b, &mut a, new);

    assert!(!a.exists(old));
    assert!(a.read(new).ends_with("A scarf.\n"));
    assert_eq!(a.read(new), b.read(new));
}

#[test]
fn two_replicas_that_move_the_same_bud_converge() {
    let (mut a, mut b) = pair();
    let moved = "Gift ideas.md";
    a.vault
        .move_to(moved, Some("Launch the newsletter.md"))
        .unwrap();
    b.vault.move_to(moved, Some("Routines")).unwrap();
    a.vault.sync().unwrap();
    b.vault.sync().unwrap();

    let a_tree = a.vault.tree_bytes().unwrap();
    let b_tree = b.vault.tree_bytes().unwrap();
    a.vault.merge_tree(&b_tree).unwrap();
    b.vault.merge_tree(&a_tree).unwrap();

    let in_a = a
        .vault
        .doc_id("Launch the newsletter/Gift ideas.md")
        .unwrap();
    let in_b = b
        .vault
        .doc_id("Launch the newsletter/Gift ideas.md")
        .unwrap();
    let routines_a = a.vault.doc_id("Routines/Gift ideas.md").unwrap();
    let routines_b = b.vault.doc_id("Routines/Gift ideas.md").unwrap();
    assert_eq!(in_a.is_some(), in_b.is_some());
    assert_eq!(routines_a.is_some(), routines_b.is_some());
    assert!(in_a.is_some() != routines_a.is_some(), "one place, not two");
    assert!(!a.exists("Gift ideas.md") && !b.exists("Gift ideas.md"));
    assert_eq!(fingerprint_no_trash(&a), fingerprint_no_trash(&b));
}

fn fingerprint_no_trash(replica: &Replica) -> BTreeMap<String, u64> {
    fingerprint(replica.dir.path())
}

#[test]
fn trashing_and_restoring_travel_through_the_tree() {
    let (mut a, mut b) = pair();
    a.vault.trash("Gift ideas.md").unwrap();
    a.vault.sync().unwrap();
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(!b.exists("Gift ideas.md"));
    assert!(b.exists(".trash/Gift ideas.md"));

    let restored = a.vault.restore(".trash/Gift ideas.md").unwrap();
    assert_eq!(restored, "Gift ideas.md");
    a.vault.sync().unwrap();
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(b.exists("Gift ideas.md"));
    assert!(!b.exists(".trash/Gift ideas.md"));
}

#[test]
fn merging_a_tree_that_matches_the_folder_writes_nothing() {
    let (a, mut b) = pair();
    let before = fingerprint(b.dir.path());
    let report = b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert_eq!((report.moved, report.written), (0, 0));
    assert_eq!(fingerprint(b.dir.path()), before);
}

#[test]
fn a_file_that_goes_leaves_no_document() {
    let mut replica = Replica::new();
    replica.vault.sync().unwrap();
    std::fs::remove_file(replica.dir.path().join("Gift ideas.md")).unwrap();
    replica.rescan_and_sync();
    assert_eq!(replica.vault.doc_id("Gift ideas.md").unwrap(), None);
}

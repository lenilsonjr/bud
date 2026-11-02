//! The scan against the fixture vault: the fictional newsletter world, nothing personal.

use bud_core::{Kind, Place, State, Vault};
use pretty_assertions::assert_eq;
use std::collections::BTreeMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")
}

/// A copy of the fixture in a temp folder, for tests that change files.
fn copy_of_fixture() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    copy_dir(&fixture(), dir.path());
    dir
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

/// Every file's bytes, by relative path, so a test can prove nothing changed.
fn fingerprint(root: &Path) -> BTreeMap<String, u64> {
    fn visit(root: &Path, dir: &Path, out: &mut BTreeMap<String, u64>) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let entry = entry.unwrap();
            if entry.file_type().unwrap().is_dir() {
                visit(root, &entry.path(), out);
            } else {
                let mut hasher = DefaultHasher::new();
                std::fs::read(entry.path()).unwrap().hash(&mut hasher);
                let rel = entry
                    .path()
                    .strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned();
                out.insert(rel, hasher.finish());
            }
        }
    }
    let mut out = BTreeMap::new();
    visit(root, root, &mut out);
    out
}

fn open(root: &Path) -> (Vault, tempfile::TempDir) {
    let index_dir = tempfile::tempdir().unwrap();
    let vault = Vault::open(root, index_dir.path().join("index.sqlite")).unwrap();
    (vault, index_dir)
}

#[test]
fn open_makes_an_empty_index_outside_the_vault() {
    let index_dir = tempfile::tempdir().unwrap();
    let index = index_dir.path().join("index.sqlite");
    let vault = Vault::open(fixture(), &index).unwrap();
    assert!(index.exists());
    assert_eq!(vault.all().unwrap(), vec![]);
    assert_eq!(vault.root(), fixture());
}

#[test]
fn open_refuses_a_file_as_a_vault() {
    let index_dir = tempfile::tempdir().unwrap();
    let err = Vault::open(
        fixture().join("Gift ideas.md"),
        index_dir.path().join("i.sqlite"),
    );
    assert!(matches!(err, Err(bud_core::Error::NotAFolder(_))));
}

#[test]
fn scans_every_bud_and_nothing_else() {
    let (mut vault, _index) = open(&fixture());
    let report = vault.rescan().unwrap();
    assert_eq!(report.added, 13);
    let mut paths: Vec<String> = vault.all().unwrap().into_iter().map(|b| b.path).collect();
    paths.sort();
    assert_eq!(
        paths,
        vec![
            "Broken.md",
            "Routines",
            "Gift ideas.md",
            "Archive/Pilot issue.md",
            ".trash/Dropped idea.md",
            "Launch the newsletter.md",
            "Routines/Weekly review.md",
            "Launch the newsletter/Pick a name.md",
            "Launch the newsletter/Design notes.md",
            "Launch the newsletter/Set up the sender.md",
            "Inbox/Ask the printer about paper weight.md",
            "Launch the newsletter/Pick a name/Shortlist three candidates.md",
            "Launch the newsletter/Pick a name/Short names read better in the inbox.md",
        ]
        .into_iter()
        .map(String::from)
        .collect::<Vec<_>>()
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
    );
}

#[test]
fn a_file_with_a_sibling_folder_is_one_bud_with_children() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let thread = vault.bud("Launch the newsletter.md").unwrap().unwrap();
    assert_eq!(thread.title, "Launch the newsletter");
    assert_eq!(thread.kind, Kind::Todo);
    assert_eq!(thread.state, Some(State::Open));
    assert_eq!(thread.parent, None);
    assert_eq!(thread.created.as_deref(), Some("2026-10-01T09:00:00Z"));
    assert_eq!(
        thread.body,
        "The first issue goes out in November. Warm, not corporate.\n"
    );

    let kids: Vec<String> = vault
        .children("Launch the newsletter.md")
        .unwrap()
        .into_iter()
        .map(|b| b.title)
        .collect();
    assert_eq!(
        kids,
        vec!["Design notes", "Pick a name", "Set up the sender"]
    );

    let name = vault
        .bud("Launch the newsletter/Pick a name.md")
        .unwrap()
        .unwrap();
    assert_eq!(name.parent.as_deref(), Some("Launch the newsletter.md"));
    assert_eq!(name.due.as_deref(), Some("2026-11-03"));
    let grandkids: Vec<String> = vault
        .children("Launch the newsletter/Pick a name.md")
        .unwrap()
        .into_iter()
        .map(|b| b.title)
        .collect();
    assert_eq!(
        grandkids,
        vec![
            "Shortlist three candidates",
            "Short names read better in the inbox"
        ]
    );
}

#[test]
fn a_folder_without_a_file_is_a_bud_with_an_empty_body() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let routines = vault.bud("Routines").unwrap().unwrap();
    assert_eq!(routines.title, "Routines");
    assert_eq!(routines.kind, Kind::Note);
    assert_eq!(routines.body, "");
    assert_eq!(routines.parent, None);
    let review = vault.bud("Routines/Weekly review.md").unwrap().unwrap();
    assert_eq!(review.parent.as_deref(), Some("Routines"));
    assert_eq!(review.when.as_deref(), Some("2026-11-02"));
    assert_eq!(review.created, None);
}

#[test]
fn reserved_roots_are_places_and_dot_folders_are_skipped() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let capture = vault
        .bud("Inbox/Ask the printer about paper weight.md")
        .unwrap()
        .unwrap();
    assert_eq!(capture.place, Place::Inbox);
    assert_eq!(capture.parent, None);
    assert_eq!(capture.source.as_deref(), Some("phone"));
    assert_eq!(
        vault.bud("Archive/Pilot issue.md").unwrap().unwrap().place,
        Place::Archive
    );
    assert_eq!(
        vault.bud(".trash/Dropped idea.md").unwrap().unwrap().place,
        Place::Trash
    );
    assert_eq!(vault.bud("Inbox").unwrap(), None);
    assert_eq!(vault.bud("Archive").unwrap(), None);
    assert_eq!(vault.bud(".trash").unwrap(), None);
    assert_eq!(vault.bud(".obsidian").unwrap(), None);
    assert_eq!(vault.bud(".obsidian/app.json").unwrap(), None);
    assert_eq!(vault.bud("notes.txt").unwrap(), None);
    let roots: Vec<String> = vault
        .roots(Place::Everything)
        .unwrap()
        .into_iter()
        .map(|b| b.title)
        .collect();
    assert_eq!(
        roots,
        vec!["Launch the newsletter", "Broken", "Gift ideas", "Routines"]
    );
    assert_eq!(vault.roots(Place::Inbox).unwrap().len(), 1);
}

#[test]
fn bad_frontmatter_is_a_note_and_pinned_reads_true() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let broken = vault.bud("Broken.md").unwrap().unwrap();
    assert_eq!(broken.kind, Kind::Note);
    assert_eq!(broken.state, None);
    assert_eq!(broken.body, "A file whose frontmatter does not parse.\n");
    let gifts = vault.bud("Gift ideas.md").unwrap().unwrap();
    assert!(gifts.pinned);
    assert_eq!(gifts.kind, Kind::Note);
    let notes = vault
        .bud("Launch the newsletter/Design notes.md")
        .unwrap()
        .unwrap();
    assert_eq!(notes.kind, Kind::Note);
    assert_eq!(notes.body, "## Voice\n\nWarm, not corporate.\n");
}

#[test]
fn a_second_scan_changes_nothing_and_a_removed_file_leaves() {
    let copy = copy_of_fixture();
    let (mut vault, _index) = open(copy.path());
    let first = vault.rescan().unwrap();
    assert_eq!(first.added, 13);
    let second = vault.rescan().unwrap();
    assert!(second.is_unchanged(), "{second:?}");

    std::fs::remove_file(copy.path().join("Gift ideas.md")).unwrap();
    let third = vault.rescan().unwrap();
    assert_eq!(third.removed, 1);
    assert_eq!(vault.bud("Gift ideas.md").unwrap(), None);
}

#[test]
fn a_file_that_gains_a_sibling_folder_keeps_its_row_and_the_folder_bud_goes() {
    let copy = copy_of_fixture();
    let (mut vault, _index) = open(copy.path());
    vault.rescan().unwrap();
    std::fs::write(copy.path().join("Routines.md"), "---\nstate: open\n---\n").unwrap();
    let report = vault.rescan().unwrap();
    assert_eq!((report.added, report.removed), (1, 1));
    assert_eq!(vault.bud("Routines").unwrap(), None);
    let review = vault.bud("Routines/Weekly review.md").unwrap().unwrap();
    assert_eq!(review.parent.as_deref(), Some("Routines.md"));
}

#[test]
fn the_vault_is_never_written() {
    let before = fingerprint(&fixture());
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    vault.rescan().unwrap();
    vault.all().unwrap();
    vault.children("Launch the newsletter.md").unwrap();
    assert_eq!(fingerprint(&fixture()), before);
}

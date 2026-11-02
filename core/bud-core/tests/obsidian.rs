//! A small Obsidian vault opens unchanged: every note is indexed, nothing is written back
//! (ADR-001 consequence 1, ADR-002 consequence 1).

use bud_core::{Kind, Place, Vault};
use pretty_assertions::assert_eq;
use std::collections::BTreeMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/obsidian")
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
fn the_fixture_looks_like_a_vault() {
    let root = fixture();
    for path in [
        ".obsidian/app.json",
        ".obsidian/workspace.json",
        "Daily/2026-11-01.md",
        "Daily/2026-11-02.md",
        "Reading list.md",
        "Linked note.md",
        "image.png",
        "Projects/Projects.md",
        "Templates/Daily template.md",
        ".trash/Old draft.md",
    ] {
        assert!(root.join(path).is_file(), "{path}");
    }
}

#[test]
fn every_markdown_file_is_a_note_and_folders_are_buds() {
    let (mut vault, _index) = open(&fixture());
    assert_eq!(vault.rescan().unwrap().added, 11);
    let mut rows: Vec<(String, Kind, bool, Place)> = vault
        .all()
        .unwrap()
        .into_iter()
        .map(|b| (b.path, b.kind, b.state.is_some(), b.place))
        .collect();
    rows.sort_by(|a, b| a.0.cmp(&b.0));
    let note = |path: &str, place| (path.to_string(), Kind::Note, false, place);
    assert_eq!(
        rows,
        vec![
            note(".trash/Old draft.md", Place::Trash),
            note("Daily", Place::Everything),
            note("Daily/2026-11-01.md", Place::Everything),
            note("Daily/2026-11-02.md", Place::Everything),
            note("Linked note.md", Place::Everything),
            note("Other note.md", Place::Everything),
            note("Projects", Place::Everything),
            note("Projects/Projects.md", Place::Everything),
            note("Reading list.md", Place::Everything),
            note("Templates", Place::Everything),
            note("Templates/Daily template.md", Place::Everything),
        ]
    );
    for folder in ["Daily", "Projects", "Templates"] {
        assert_eq!(vault.bud(folder).unwrap().unwrap().body, "", "{folder}");
    }
}

#[test]
fn settings_and_attachments_are_skipped_and_the_trash_is_a_place() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    assert_eq!(vault.bud(".obsidian").unwrap(), None);
    assert_eq!(vault.bud(".obsidian/app.json").unwrap(), None);
    assert_eq!(vault.bud(".obsidian/workspace.json").unwrap(), None);
    assert_eq!(vault.bud("image.png").unwrap(), None);
    assert_eq!(vault.bud(".trash").unwrap(), None);
    let trashed = vault.bud(".trash/Old draft.md").unwrap().unwrap();
    assert_eq!(trashed.place, Place::Trash);
    assert_eq!(trashed.parent, None);
}

#[test]
fn a_folder_note_is_a_child_of_its_folder() {
    // ADR-002 consequence 2: `Projects/Projects.md` is not merged into the folder. It is a bud
    // under the `Projects` folder bud. Changing this is a decision, so this test names it.
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let folder = vault.bud("Projects").unwrap().unwrap();
    assert_eq!(folder.parent, None);
    let note = vault.bud("Projects/Projects.md").unwrap().unwrap();
    assert_eq!(note.parent.as_deref(), Some("Projects"));
    assert_eq!(note.title, "Projects");
    let kids: Vec<String> = vault
        .children("Projects")
        .unwrap()
        .into_iter()
        .map(|b| b.path)
        .collect();
    assert_eq!(kids, vec!["Projects/Projects.md"]);
}

#[test]
fn wiki_links_and_embeds_stay_as_text_in_the_body() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let linked = vault.bud("Linked note.md").unwrap().unwrap();
    assert_eq!(
        linked.body,
        "See [[Other note]] for the long version.\n\n![[image.png]]\n\nAlso [[Reading list|the shelf]].\n"
    );
}

#[test]
fn frontmatter_with_tags_and_aliases_is_a_note_and_its_body_is_intact() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    let reading = vault.bud("Reading list.md").unwrap().unwrap();
    assert_eq!(reading.kind, Kind::Note);
    assert_eq!(reading.state, None);
    assert_eq!(
        reading.body,
        "\nTitles to look at before the first issue goes out.\n"
    );
}

#[test]
fn a_second_scan_changes_nothing() {
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    assert!(vault.rescan().unwrap().is_unchanged());
}

#[test]
fn the_vault_bytes_are_identical_after_every_read() {
    let before = fingerprint(&fixture());
    assert_eq!(before.len(), 11);
    let (mut vault, _index) = open(&fixture());
    vault.rescan().unwrap();
    vault.rescan().unwrap();
    assert_eq!(vault.search("shelf", 10).unwrap().len(), 1);
    assert!(vault.today("2026-11-02").unwrap().is_empty());
    assert_eq!(vault.counts("Projects").unwrap().inside, 1);
    assert_eq!(vault.counts("Daily").unwrap().inside, 2);
    assert_eq!(fingerprint(&fixture()), before);
}

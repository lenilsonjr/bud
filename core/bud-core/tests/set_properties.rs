//! Writing properties through the vault: one file changes, its body does not, the index follows.

use bud_core::{split_frontmatter, Properties, State, Vault};
use pretty_assertions::assert_eq;
use std::path::Path;

const SOURCE: &str = "---\n# written by hand\ntags: [brand, 'launch']\naliases:\n  - Sender\nstate: open\n---\nDomain records are in the shared doc.\n\nSecond paragraph.\n";

fn vault_with(files: &[(&str, &str)]) -> (Vault, tempfile::TempDir, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    for (name, text) in files {
        let path = dir.path().join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    let index = tempfile::tempdir().unwrap();
    let mut vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    vault.rescan().unwrap();
    (vault, dir, index)
}

fn body_of(root: &Path, name: &str) -> String {
    let text = std::fs::read_to_string(root.join(name)).unwrap();
    split_frontmatter(&text).1.to_string()
}

#[test]
fn sets_one_key_and_leaves_the_rest_of_the_file_alone() {
    let (mut vault, dir, _index) = vault_with(&[("Set up the sender.md", SOURCE)]);
    let before = body_of(dir.path(), "Set up the sender.md");
    let bud = vault.bud("Set up the sender.md").unwrap().unwrap();
    let props = Properties {
        state: Some(State::Done),
        ..Default::default()
    };
    vault.set_properties(&bud.path, &props).unwrap();

    let text = std::fs::read_to_string(dir.path().join("Set up the sender.md")).unwrap();
    assert_eq!(
        text,
        SOURCE.replace("state: open", "state: done"),
        "only the state line changes"
    );
    assert_eq!(body_of(dir.path(), "Set up the sender.md"), before);
    let after = vault.bud("Set up the sender.md").unwrap().unwrap();
    assert_eq!(after.state, Some(State::Done));
    assert_eq!(after.body, bud.body);
    assert!(!dir.path().join("Set up the sender.md.tmp").exists());
}

#[test]
fn the_row_follows_every_property() {
    let (mut vault, _dir, _index) = vault_with(&[("Note.md", "Just a note\n")]);
    let props = Properties {
        state: Some(State::Open),
        when: Some("2026-11-02".into()),
        due: Some("2026-11-05".into()),
        pinned: true,
        created: Some("2026-10-02T11:00:00Z".into()),
        source: Some("phone".into()),
        from: None,
        from_state: None,
    };
    vault.set_properties("Note.md", &props).unwrap();
    let bud = vault.bud("Note.md").unwrap().unwrap();
    assert!(bud.is_todo());
    assert_eq!(bud.when.as_deref(), Some("2026-11-02"));
    assert_eq!(bud.due.as_deref(), Some("2026-11-05"));
    assert!(bud.pinned);
    assert_eq!(bud.created.as_deref(), Some("2026-10-02T11:00:00Z"));
    assert_eq!(bud.source.as_deref(), Some("phone"));
    assert_eq!(bud.body, "Just a note\n");

    vault
        .set_properties("Note.md", &Properties::default())
        .unwrap();
    let bud = vault.bud("Note.md").unwrap().unwrap();
    assert!(!bud.is_todo());
    assert!(!bud.pinned);
    assert_eq!(bud.due, None);
}

#[test]
fn a_folder_only_bud_gets_a_file_beside_it_and_keeps_its_children() {
    let (mut vault, dir, _index) = vault_with(&[("Thread/Child.md", "Child body\n")]);
    assert!(vault.bud("Thread").unwrap().is_some());
    let props = Properties {
        state: Some(State::Open),
        ..Default::default()
    };
    vault.set_properties("Thread", &props).unwrap();

    let text = std::fs::read_to_string(dir.path().join("Thread.md")).unwrap();
    assert_eq!(text, "---\nstate: open\n---\n");
    assert!(dir.path().join("Thread").is_dir());
    assert!(vault.bud("Thread").unwrap().is_none());
    let bud = vault.bud("Thread.md").unwrap().unwrap();
    assert_eq!(bud.title, "Thread");
    assert_eq!(bud.state, Some(State::Open));
    let children = vault.children("Thread.md").unwrap();
    assert_eq!(children.len(), 1);
    assert_eq!(children[0].path, "Thread/Child.md");

    // A rescan agrees with what set_properties left in the index.
    let before = vault.all().unwrap();
    vault.rescan().unwrap();
    assert_eq!(vault.all().unwrap(), before);
}

#[test]
fn an_unknown_path_is_an_error_and_writes_nothing() {
    let (mut vault, dir, _index) = vault_with(&[("Note.md", "x")]);
    let err = vault
        .set_properties("Missing.md", &Properties::default())
        .unwrap_err();
    assert!(matches!(err, bud_core::Error::NoSuchBud(_)));
    assert!(!dir.path().join("Missing.md").exists());
}

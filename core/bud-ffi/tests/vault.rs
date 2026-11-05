//! The FFI surface, called the way Swift calls it: through `Vault` and the records.

use bud_ffi::{
    open_vault, BudKind, BudPlace, BudState, Vault, VaultError, VaultLens, VaultListener,
};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

struct Fixture {
    vault: Arc<Vault>,
    dir: tempfile::TempDir,
    _index: tempfile::TempDir,
}

fn fixture(files: &[(&str, &str)]) -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    for (name, text) in files {
        let path = dir.path().join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    let index = tempfile::tempdir().unwrap();
    let vault = open_vault(
        dir.path().to_str().unwrap().to_string(),
        index.path().join("index.db").to_str().unwrap().to_string(),
    )
    .unwrap();
    Fixture {
        vault,
        dir,
        _index: index,
    }
}

const DONE_TODO: &str = "---\nstate: done\n---\nShipped.\n";
const OPEN_TODO: &str =
    "---\nstate: open\ndue: 2026-11-01\npinned: true\ncreated: 2026-10-01\n---\nWrite the issue.\n";

fn newsletter() -> Fixture {
    fixture(&[
        ("Newsletter.md", "A note about the newsletter.\n"),
        ("Newsletter/Draft issue.md", OPEN_TODO),
        ("Newsletter/Send.md", DONE_TODO),
    ])
}

#[test]
fn open_vault_fills_the_index() {
    let f = newsletter();
    let paths: Vec<String> = f
        .vault
        .snapshot()
        .unwrap()
        .into_iter()
        .map(|b| b.path)
        .collect();
    assert!(paths.contains(&"Newsletter.md".to_string()));
    assert!(paths.contains(&"Newsletter/Draft issue.md".to_string()));
}

#[test]
fn a_record_is_flat() {
    let f = newsletter();
    let bud = f
        .vault
        .bud("Newsletter/Draft issue.md".into())
        .unwrap()
        .unwrap();
    assert_eq!(bud.parent.as_deref(), Some("Newsletter.md"));
    assert_eq!(bud.title, "Draft issue");
    assert_eq!(bud.kind, BudKind::Todo);
    assert_eq!(bud.state, Some(BudState::Open));
    assert_eq!(bud.due.as_deref(), Some("2026-11-01"));
    assert!(bud.pinned);
    assert_eq!(bud.created.as_deref(), Some("2026-10-01"));
    assert_eq!(bud.place, BudPlace::Everything);
    assert_eq!(bud.body, "Write the issue.\n");
    assert!(f.vault.bud("Nothing.md".into()).unwrap().is_none());
}

#[test]
fn children_are_the_direct_ones() {
    let f = newsletter();
    let titles: Vec<String> = f
        .vault
        .children("Newsletter.md".into())
        .unwrap()
        .into_iter()
        .map(|b| b.title)
        .collect();
    assert_eq!(titles.len(), 2);
    assert!(titles.contains(&"Send".to_string()));
}

#[test]
fn edits_change_the_file_and_the_index() {
    let f = newsletter();
    let path = f
        .vault
        .create(
            Some("Newsletter.md".into()),
            "Pick a subject".into(),
            BudKind::Todo,
            None,
        )
        .unwrap();
    assert_eq!(path, "Newsletter/Pick a subject.md");
    f.vault
        .set_body(path.clone(), "Three options.\n".into())
        .unwrap();
    f.vault
        .set_state(path.clone(), Some(BudState::Done))
        .unwrap();
    f.vault.set_pinned(path.clone(), true).unwrap();
    let bud = f.vault.bud(path.clone()).unwrap().unwrap();
    assert_eq!(bud.state, Some(BudState::Done));
    assert!(bud.pinned);
    assert_eq!(bud.body, "Three options.\n");
    let on_disk = std::fs::read_to_string(f.dir.path().join(&path)).unwrap();
    assert!(on_disk.ends_with("Three options.\n"));

    let renamed = f.vault.rename(path, "Choose a subject".into()).unwrap();
    assert_eq!(renamed, "Newsletter/Choose a subject.md");
    let moved = f.vault.move_to(renamed, None).unwrap();
    assert_eq!(moved, "Choose a subject.md");
}

#[test]
fn trash_and_restore_round_trip() {
    let f = newsletter();
    f.vault.trash("Newsletter/Send.md".into()).unwrap();
    let trashed = f
        .vault
        .bud(".trash/Newsletter/Send.md".into())
        .unwrap()
        .unwrap();
    assert_eq!(trashed.place, BudPlace::Trash);
    let back = f.vault.restore(".trash/Newsletter/Send.md".into()).unwrap();
    assert_eq!(back, "Newsletter/Send.md");
}

#[test]
fn when_due_and_deleting_from_the_trash() {
    let f = newsletter();
    let path = "Newsletter/Draft issue.md".to_string();
    f.vault
        .set_when(path.clone(), Some("2026-11-02".into()))
        .unwrap();
    f.vault.set_due(path.clone(), None).unwrap();
    f.vault.set_state(path.clone(), None).unwrap();
    let bud = f.vault.bud(path.clone()).unwrap().unwrap();
    assert_eq!(bud.when.as_deref(), Some("2026-11-02"));
    assert_eq!(bud.due, None);
    assert_eq!((bud.kind, bud.state), (BudKind::Note, None));

    assert!(matches!(
        f.vault.delete_forever(path.clone()).unwrap_err(),
        VaultError::Invalid { .. }
    ));
    f.vault.trash(path).unwrap();
    f.vault.trash("Newsletter/Send.md".into()).unwrap();
    f.vault
        .delete_forever(".trash/Newsletter/Draft issue.md".into())
        .unwrap();
    assert!(!f
        .dir
        .path()
        .join(".trash/Newsletter/Draft issue.md")
        .exists());
    assert!(f
        .vault
        .bud(".trash/Newsletter/Send.md".into())
        .unwrap()
        .is_some());
    f.vault.empty_trash().unwrap();
    let left: Vec<String> = f
        .vault
        .snapshot()
        .unwrap()
        .into_iter()
        .map(|b| b.path)
        .collect();
    assert_eq!(left, ["Newsletter.md"]);
}

#[test]
fn queries_answer_from_the_index() {
    let f = newsletter();
    let hits = f.vault.search("draft".into(), 10).unwrap();
    assert_eq!(hits[0].path, "Newsletter/Draft issue.md");
    assert_eq!(hits[0].trail, vec!["Newsletter".to_string()]);

    let today = f.vault.today("2026-11-02".into()).unwrap();
    assert_eq!(today.len(), 1);
    assert_eq!(today[0].bud.path, "Newsletter/Draft issue.md");

    let counts = f.vault.counts("Newsletter.md".into()).unwrap();
    assert_eq!((counts.inside, counts.open_todos), (2, 1));

    let next = f
        .vault
        .next_step(None, "2026-11-02".into())
        .unwrap()
        .unwrap();
    assert_eq!(next.bud.title, "Draft issue");
    assert!(f
        .vault
        .next_step(Some("Newsletter/Send.md".into()), "2026-11-02".into())
        .unwrap()
        .is_none());

    assert_eq!(f.vault.lens(VaultLens::Todos).unwrap().len(), 1);
    assert_eq!(f.vault.lens(VaultLens::Pinned).unwrap().len(), 1);
}

#[test]
fn errors_are_one_enum() {
    let f = newsletter();
    let missing = f.vault.set_body("Nothing.md".into(), "x".into());
    assert!(matches!(missing, Err(VaultError::NoSuchBud { .. })));
    let not_a_folder = open_vault("/no/such/folder".into(), "/tmp/unused.db".into());
    assert!(matches!(not_a_folder, Err(VaultError::NotAFolder { .. })));
    let twice = f.vault.restore("Newsletter/Send.md".into());
    assert!(matches!(twice, Err(VaultError::Invalid { .. })));
}

struct Collect(Mutex<Sender<Vec<String>>>);

impl VaultListener for Collect {
    fn changed(&self, paths: Vec<String>) {
        let _ = self.0.lock().unwrap().send(paths);
    }
}

#[test]
fn the_listener_hears_a_change_made_outside() {
    let f = newsletter();
    let (tx, rx) = channel();
    let _watch = f.vault.watch(Box::new(Collect(Mutex::new(tx)))).unwrap();
    std::thread::sleep(Duration::from_millis(300));
    std::fs::write(f.dir.path().join("Newsletter/Outside.md"), "Hello.\n").unwrap();
    let paths = rx.recv_timeout(Duration::from_secs(10)).unwrap();
    assert!(paths.iter().any(|p| p == "Newsletter/Outside.md"));
    assert!(f
        .vault
        .bud("Newsletter/Outside.md".into())
        .unwrap()
        .is_some());
}

#[test]
fn tags_are_added_removed_and_renamed() {
    let f = fixture(&[("Groceries.md", "---\ntags: [home]\n---\nMilk #home\n")]);
    let path = "Groceries.md".to_string();
    f.vault.add_tag(path.clone(), "errands".into()).unwrap();
    f.vault.remove_tag(path.clone(), "home".into()).unwrap();
    assert_eq!(f.vault.tags_of(path.clone()).unwrap(), ["errands", "home"]);
    let edits = f.vault.rename_tag("home".into(), "house".into()).unwrap();
    assert_eq!(edits.len(), 1);
    let read = || std::fs::read_to_string(f.dir.path().join("Groceries.md")).unwrap();
    assert_eq!(read(), "---\ntags: [errands]\n---\nMilk #house\n");
    assert!(f
        .vault
        .restore_text(path, edits[0].after.clone(), edits[0].before.clone())
        .unwrap());
    assert_eq!(read(), "---\ntags: [errands]\n---\nMilk #home\n");
}

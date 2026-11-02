//! The watcher: the index follows the folder and the listener hears one callback per batch.

use bud_core::{Place, Properties, State, Vault, VaultListener};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;
use std::time::{Duration, Instant};

struct Collect(Mutex<Sender<Vec<String>>>);

impl VaultListener for Collect {
    fn changed(&self, paths: Vec<String>) {
        let _ = self.0.lock().unwrap().send(paths);
    }
}

struct Fixture {
    vault: Vault,
    dir: tempfile::TempDir,
    _index: tempfile::TempDir,
    batches: Receiver<Vec<String>>,
    listener: Box<Collect>,
}

fn fixture(files: &[(&str, &str)]) -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    for (name, text) in files {
        let path = dir.path().join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    let index = tempfile::tempdir().unwrap();
    let mut vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    vault.rescan().unwrap();
    let (tx, batches) = channel();
    Fixture {
        vault,
        dir,
        _index: index,
        batches,
        listener: Box::new(Collect(Mutex::new(tx))),
    }
}

fn wait_for(mut condition: impl FnMut() -> bool, within: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < within {
        if condition() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    condition()
}

#[test]
fn a_file_written_after_watch_shows_up_in_the_index() {
    let f = fixture(&[]);
    let _watch = f.vault.watch(f.listener).unwrap();
    std::fs::write(f.dir.path().join("Pick a name.md"), "Ideas.\n").unwrap();
    assert!(wait_for(
        || f.vault.bud("Pick a name.md").unwrap().is_some(),
        Duration::from_secs(2)
    ));
    let paths = f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    assert_eq!(paths, vec!["Pick a name.md".to_string()]);
}

#[test]
fn a_burst_of_five_files_is_one_callback_with_five_paths() {
    let f = fixture(&[]);
    let _watch = f.vault.watch(f.listener).unwrap();
    for n in 1..=5 {
        std::fs::write(f.dir.path().join(format!("Candidate {n}.md")), "x\n").unwrap();
    }
    let mut paths = f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    paths.sort();
    let expected: Vec<String> = (1..=5).map(|n| format!("Candidate {n}.md")).collect();
    assert_eq!(paths, expected);
    assert!(f.batches.recv_timeout(Duration::from_millis(600)).is_err());
    assert_eq!(f.vault.all().unwrap().len(), 5);
}

#[test]
fn modify_remove_and_rename_reindex_only_the_paths_touched() {
    let f = fixture(&[
        ("Keep.md", "Same.\n"),
        ("Change.md", "Before.\n"),
        ("Drop.md", "Gone soon.\n"),
        ("Old name.md", "Moves.\n"),
    ]);
    let _watch = f.vault.watch(f.listener).unwrap();
    std::fs::write(f.dir.path().join("Change.md"), "After.\n").unwrap();
    std::fs::remove_file(f.dir.path().join("Drop.md")).unwrap();
    std::fs::rename(
        f.dir.path().join("Old name.md"),
        f.dir.path().join("New name.md"),
    )
    .unwrap();
    let mut paths = f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    paths.sort();
    assert_eq!(
        paths,
        vec!["Change.md", "Drop.md", "New name.md", "Old name.md"]
    );
    assert_eq!(f.vault.bud("Change.md").unwrap().unwrap().body, "After.\n");
    assert!(f.vault.bud("Drop.md").unwrap().is_none());
    assert!(f.vault.bud("Old name.md").unwrap().is_none());
    assert!(f.vault.bud("New name.md").unwrap().is_some());
    assert!(f.vault.bud("Keep.md").unwrap().is_some());
}

#[test]
fn the_index_own_write_does_not_echo() {
    let mut f = fixture(&[("Set up the sender.md", "---\nstate: open\n---\nBody.\n")]);
    let _watch = f.vault.watch(f.listener).unwrap();
    let props = Properties {
        state: Some(State::Done),
        ..Default::default()
    };
    f.vault
        .set_properties("Set up the sender.md", &props)
        .unwrap();
    assert!(f.batches.recv_timeout(Duration::from_millis(900)).is_err());
    let bud = f.vault.bud("Set up the sender.md").unwrap().unwrap();
    assert_eq!(bud.state, Some(State::Done));
}

#[test]
fn dot_folders_and_other_files_are_ignored_and_the_trash_is_watched() {
    let f = fixture(&[(".trash/Dropped idea.md", "Old.\n")]);
    std::fs::create_dir_all(f.dir.path().join(".obsidian")).unwrap();
    let _watch = f.vault.watch(f.listener).unwrap();
    std::fs::write(f.dir.path().join(".obsidian/Note.md"), "x\n").unwrap();
    std::fs::write(f.dir.path().join("notes.txt"), "x\n").unwrap();
    std::fs::write(f.dir.path().join(".hidden.md"), "x\n").unwrap();
    assert!(f.batches.recv_timeout(Duration::from_millis(900)).is_err());
    assert_eq!(f.vault.all().unwrap().len(), 1);

    std::fs::write(f.dir.path().join(".trash/Another idea.md"), "x\n").unwrap();
    let paths = f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    assert_eq!(paths, vec![".trash/Another idea.md"]);
    let bud = f.vault.bud(".trash/Another idea.md").unwrap().unwrap();
    assert_eq!(bud.place, Place::Trash);
}

#[test]
fn a_folder_removed_mid_burst_does_not_stop_the_watcher() {
    let f = fixture(&[("Thread/One.md", "x\n"), ("Thread/Two.md", "x\n")]);
    let _watch = f.vault.watch(f.listener).unwrap();
    std::fs::write(f.dir.path().join("Thread/Three.md"), "x\n").unwrap();
    std::fs::remove_dir_all(f.dir.path().join("Thread")).unwrap();
    let _ = f.batches.recv_timeout(Duration::from_secs(2));
    std::thread::sleep(Duration::from_millis(400));
    while f.batches.try_recv().is_ok() {}
    assert!(f.vault.all().unwrap().is_empty());

    std::fs::write(f.dir.path().join("After.md"), "x\n").unwrap();
    let paths = f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    assert_eq!(paths, vec!["After.md"]);
    assert!(f.vault.bud("After.md").unwrap().is_some());
}

#[test]
fn a_file_beside_a_folder_bud_takes_its_children() {
    let f = fixture(&[("Launch/Pick a name.md", "x\n")]);
    assert_eq!(f.vault.children("Launch").unwrap().len(), 1);
    let _watch = f.vault.watch(f.listener).unwrap();
    std::fs::write(f.dir.path().join("Launch.md"), "Plan.\n").unwrap();
    f.batches.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(f.vault.bud("Launch").unwrap().is_none());
    assert_eq!(f.vault.children("Launch.md").unwrap().len(), 1);
}

#[test]
fn dropping_the_watch_stops_it() {
    let f = fixture(&[]);
    let watch = f.vault.watch(f.listener).unwrap();
    drop(watch);
    std::fs::write(f.dir.path().join("Late.md"), "x\n").unwrap();
    assert!(f.batches.recv_timeout(Duration::from_millis(800)).is_err());
    assert!(f.vault.bud("Late.md").unwrap().is_none());
}

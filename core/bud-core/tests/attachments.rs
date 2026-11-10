//! Pictures in the index and the embeds that show them: what the scan keeps, what an embed
//! resolves to, and how both follow the folder.

use bud_core::{Embed, Vault, VaultListener};
use pretty_assertions::assert_eq;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;
use std::time::{Duration, Instant};

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

fn to(embeds: &[Embed]) -> Vec<(&str, Option<&str>)> {
    embeds
        .iter()
        .map(|e| (e.target.as_str(), e.to.as_deref()))
        .collect()
}

const WORLD: &[(&str, &str)] = &[
    (
        "Launch.md",
        "The cover: ![[cover.png]] then ![[COVER.png]], ![](Launch/proofs.jpg), ![[Twin.png]], ![[Nowhere.png]].\n",
    ),
    ("cover.png", "png bytes"),
    ("Launch/proofs.jpg", "jpg bytes"),
    ("Launch/Twin.png", "a"),
    ("Garden/Twin.png", "b"),
    ("Garden.md", "![spread](Twin.png) and ![](Garden/Twin.png)\n"),
    ("Kitchen.md", "Which ![[Twin.png]]?\n"),
    ("notes.txt", "not a picture"),
    (".trash/Old.md", "![[cover.png]]\n"),
    (".trash/old.png", "gone"),
];

#[test]
fn every_picture_is_an_attachment_with_its_size_and_time_and_nothing_else_is() {
    let (vault, dir, _index) = vault_with(WORLD);
    let found: Vec<(String, String, u64)> = vault
        .attachments()
        .unwrap()
        .into_iter()
        .map(|a| (a.path, a.name, a.size))
        .collect();
    assert_eq!(
        found,
        vec![
            (".trash/old.png".into(), "old.png".into(), 4),
            ("Garden/Twin.png".into(), "Twin.png".into(), 1),
            ("Launch/Twin.png".into(), "Twin.png".into(), 1),
            ("Launch/proofs.jpg".into(), "proofs.jpg".into(), 9),
            ("cover.png".into(), "cover.png".into(), 9),
        ]
    );
    let cover = vault.attachment("cover.png").unwrap().unwrap();
    let on_disk = std::fs::metadata(dir.path().join("cover.png")).unwrap();
    assert_eq!(cover.size, on_disk.len());
    assert!(cover.mtime > 0);
    assert_eq!(vault.attachment("notes.txt").unwrap(), None);
    assert_eq!(vault.bud("cover.png").unwrap(), None, "a picture is no bud");
}

#[test]
fn embeds_resolve_by_name_then_any_case_then_path_and_twins_elsewhere_resolve_to_nothing() {
    let (vault, _dir, _index) = vault_with(WORLD);
    assert_eq!(
        to(&vault.embeds("Launch.md").unwrap()),
        vec![
            ("cover.png", Some("cover.png")),
            ("COVER.png", Some("cover.png")),
            ("Launch/proofs.jpg", Some("Launch/proofs.jpg")),
            ("Twin.png", Some("Launch/Twin.png")),
            ("Nowhere.png", None),
        ]
    );
    assert_eq!(
        to(&vault.embeds("Kitchen.md").unwrap()),
        vec![("Twin.png", None)],
        "two pictures with one name, neither near the bud, are none"
    );
    let garden = vault.embeds("Garden.md").unwrap();
    assert_eq!(
        to(&garden),
        vec![
            ("Twin.png", Some("Garden/Twin.png")),
            ("Garden/Twin.png", Some("Garden/Twin.png"))
        ],
        "among twins, the one in the bud's own folder wins"
    );
    assert_eq!(garden[0].label.as_deref(), Some("spread"));
    assert!(
        vault.links("Launch.md").unwrap().is_empty(),
        "an embed is no link"
    );
}

#[test]
fn among_twins_the_one_beside_the_buds_file_wins_when_its_own_folder_has_none() {
    let (vault, _dir, _index) = vault_with(&[
        ("Launch/Pick a name.md", "![](Twin.png) ![](./Twin.png)\n"),
        ("Launch/Twin.png", "a"),
        ("Garden/Twin.png", "b"),
    ]);
    assert_eq!(
        to(&vault.embeds("Launch/Pick a name.md").unwrap()),
        vec![
            ("Twin.png", Some("Launch/Twin.png")),
            ("./Twin.png", Some("Launch/Twin.png"))
        ]
    );
}

#[test]
fn the_first_embed_is_the_first_that_names_a_picture() {
    let (vault, _dir, _index) = vault_with(&[
        (
            "Card.md",
            "![[Nowhere.png]] then ![[cover.png|wide]] and ![[cover.png]]\n",
        ),
        ("Plain.md", "No picture here.\n"),
        ("cover.png", "png bytes"),
    ]);
    let first = vault.first_embed("Card.md").unwrap().unwrap();
    assert_eq!(first.to.as_deref(), Some("cover.png"));
    assert_eq!(first.label.as_deref(), Some("wide"));
    assert_eq!(vault.first_embed("Plain.md").unwrap(), None);
    assert_eq!(vault.first_embed("Nothing.md").unwrap(), None);
}

#[test]
fn a_picture_knows_the_buds_that_embed_it_and_trash_does_not_count() {
    let (vault, _dir, _index) = vault_with(WORLD);
    let who: Vec<(String, String)> = vault
        .embedding("cover.png")
        .unwrap()
        .into_iter()
        .map(|e| (e.from, e.target))
        .collect();
    assert_eq!(
        who,
        vec![
            ("Launch.md".into(), "cover.png".into()),
            ("Launch.md".into(), "COVER.png".into())
        ],
        "the trashed bud's embed is left out"
    );
    let who: Vec<String> = vault
        .embedding("Launch/proofs.jpg")
        .unwrap()
        .into_iter()
        .map(|e| e.from)
        .collect();
    assert_eq!(who, ["Launch.md"]);
    let who = |path: &str| -> Vec<String> {
        vault
            .embedding(path)
            .unwrap()
            .into_iter()
            .map(|e| e.from)
            .collect()
    };
    assert_eq!(who("Garden/Twin.png"), ["Garden.md", "Garden.md"]);
    assert_eq!(who("Launch/Twin.png"), ["Launch.md"]);
    assert!(vault.embedding(".trash/old.png").unwrap().is_empty());
    assert!(vault.embedding("Nowhere.png").unwrap().is_empty());
}

#[test]
fn a_rescan_follows_pictures_that_come_change_and_go() {
    let (mut vault, dir, _index) = vault_with(&[("Note.md", "![[new.png]]\n")]);
    assert_eq!(vault.embeds("Note.md").unwrap()[0].to, None);
    std::fs::write(dir.path().join("new.png"), "one").unwrap();
    let report = vault.rescan().unwrap();
    assert_eq!((report.added, report.updated, report.removed), (1, 0, 0));
    assert_eq!(
        vault.embeds("Note.md").unwrap()[0].to.as_deref(),
        Some("new.png"),
        "an embed finds a picture added after it"
    );
    assert!(vault.rescan().unwrap().is_unchanged());

    std::fs::write(dir.path().join("new.png"), "one more").unwrap();
    assert_eq!(vault.rescan().unwrap().updated, 1);
    assert_eq!(vault.attachment("new.png").unwrap().unwrap().size, 8);

    std::fs::remove_file(dir.path().join("new.png")).unwrap();
    assert_eq!(vault.rescan().unwrap().removed, 1);
    assert!(vault.attachments().unwrap().is_empty());
    assert_eq!(vault.embeds("Note.md").unwrap()[0].to, None);
}

#[test]
fn pictures_follow_a_rename_a_trashing_and_a_delete_of_their_bud() {
    let (mut vault, _dir, _index) = vault_with(&[
        ("Launch.md", "![[cover.png]]\n"),
        ("Launch/cover.png", "png bytes"),
    ]);
    let renamed = vault.rename("Launch.md", "Launch day").unwrap();
    assert_eq!(
        vault.attachments().unwrap()[0].path,
        "Launch day/cover.png",
        "the picture moved with its bud's folder"
    );
    assert_eq!(
        vault.embeds(&renamed).unwrap()[0].to.as_deref(),
        Some("Launch day/cover.png")
    );

    vault.trash(&renamed).unwrap();
    let paths: Vec<String> = vault
        .attachments()
        .unwrap()
        .into_iter()
        .map(|a| a.path)
        .collect();
    assert_eq!(paths.len(), 1);
    assert!(paths[0].starts_with(".trash/"));
    let trashed = vault
        .all()
        .unwrap()
        .into_iter()
        .find(|b| b.title == "Launch day")
        .unwrap();
    assert_eq!(
        vault.embeds(&trashed.path).unwrap(),
        vec![],
        "trash has no embeds"
    );

    let back = vault.restore(&trashed.path).unwrap();
    assert_eq!(
        vault.embeds(&back).unwrap()[0].to.as_deref(),
        Some("Launch day/cover.png")
    );
    vault.trash(&back).unwrap();
    vault.empty_trash().unwrap();
    assert!(vault.attachments().unwrap().is_empty());
    assert!(vault.rescan().unwrap().is_unchanged());
}

struct Collect(Mutex<Sender<Vec<String>>>);

impl VaultListener for Collect {
    fn changed(&self, paths: Vec<String>) {
        let _ = self.0.lock().unwrap().send(paths);
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

fn drain(batches: &Receiver<Vec<String>>) -> Vec<String> {
    let mut paths = Vec::new();
    while let Ok(batch) = batches.recv_timeout(Duration::from_millis(600)) {
        paths.extend(batch);
    }
    paths.sort();
    paths
}

#[test]
fn the_watcher_follows_a_picture_dropped_into_a_folder_and_taken_out_again() {
    let (vault, dir, _index) = vault_with(&[
        ("Note.md", "![](Pics/new.png)\n"),
        ("Pics/Keep.md", "A bud beside the picture.\n"),
    ]);
    let (tx, batches) = channel();
    let _watch = vault.watch(Box::new(Collect(Mutex::new(tx)))).unwrap();
    std::fs::write(dir.path().join("Pics/new.png"), "one").unwrap();
    assert!(wait_for(
        || vault.attachment("Pics/new.png").unwrap().is_some(),
        Duration::from_secs(2)
    ));
    assert_eq!(drain(&batches), vec!["Pics/new.png".to_string()]);
    assert_eq!(
        vault.first_embed("Note.md").unwrap().unwrap().to.as_deref(),
        Some("Pics/new.png")
    );

    std::fs::remove_dir_all(dir.path().join("Pics")).unwrap();
    assert!(wait_for(
        || vault.attachment("Pics/new.png").unwrap().is_none(),
        Duration::from_secs(2)
    ));
    assert_eq!(
        drain(&batches),
        vec![
            "Pics".to_string(),
            "Pics/Keep.md".to_string(),
            "Pics/new.png".to_string()
        ],
        "the folder, its bud and its picture went together"
    );
    assert_eq!(vault.first_embed("Note.md").unwrap(), None);
}

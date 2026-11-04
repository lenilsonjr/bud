//! Links between buds: what the index keeps, what it resolves to, and how it follows edits.

use bud_core::{Kind, Link, Place, Vault};
use pretty_assertions::assert_eq;

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

fn to(links: &[Link]) -> Vec<(&str, Option<&str>)> {
    links
        .iter()
        .map(|l| (l.target.as_str(), l.to.as_deref()))
        .collect()
}

const WORLD: &[(&str, &str)] = &[
    (
        "Launch.md",
        "The plan: [[Welcome list|the list]], [[welcome LIST]], [[Launch/Welcome list]], [[Nowhere]].\n",
    ),
    ("Launch/Welcome list.md", "Who gets it. Back to [[Launch]].\n"),
    ("Garden.md", "Nothing about the launch.\n"),
    ("Garden/Twin.md", ""),
    ("Kitchen/Twin.md", ""),
    ("Kitchen.md", "Which [[Twin]]?\n"),
    (".trash/Old.md", "Gone, but [[Launch]].\n"),
];

#[test]
fn links_resolve_by_title_then_any_case_then_path() {
    let (vault, _dir, _index) = vault_with(WORLD);
    let links = vault.links("Launch.md").unwrap();
    assert_eq!(
        to(&links),
        vec![
            ("Welcome list", Some("Launch/Welcome list.md")),
            ("welcome LIST", Some("Launch/Welcome list.md")),
            ("Launch/Welcome list", Some("Launch/Welcome list.md")),
            ("Nowhere", None),
        ]
    );
    assert_eq!(links[0].label.as_deref(), Some("the list"));
}

#[test]
fn backlinks_list_who_names_a_bud_and_trash_does_not_count() {
    let (vault, _dir, _index) = vault_with(WORLD);
    let back = vault.backlinks("Launch/Welcome list.md").unwrap();
    assert_eq!(back.len(), 3);
    assert!(back.iter().all(|l| l.from == "Launch.md"));
    let back = vault.backlinks("Launch.md").unwrap();
    assert_eq!(
        back.iter().map(|l| l.from.as_str()).collect::<Vec<_>>(),
        vec!["Launch/Welcome list.md"],
        "the trashed bud's link is left out"
    );
    assert!(vault.backlinks("Garden.md").unwrap().is_empty());
}

#[test]
fn two_buds_with_one_title_leave_the_link_unresolved() {
    let (vault, _dir, _index) = vault_with(WORLD);
    assert_eq!(
        to(&vault.links("Kitchen.md").unwrap()),
        vec![("Twin", None)]
    );
    let unresolved: Vec<_> = vault
        .unresolved_links()
        .unwrap()
        .into_iter()
        .map(|l| l.target)
        .collect();
    assert_eq!(
        unresolved,
        vec!["Twin".to_string(), "Nowhere".to_string()],
        "by the path they are written in"
    );
}

#[test]
fn writing_a_body_replaces_its_links() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    vault
        .set_body("Garden.md", "Now about [[Launch]] and [[Kitchen]].\n")
        .unwrap();
    assert_eq!(
        to(&vault.links("Garden.md").unwrap()),
        vec![
            ("Launch", Some("Launch.md")),
            ("Kitchen", Some("Kitchen.md"))
        ]
    );
    vault.set_body("Garden.md", "Nothing again.\n").unwrap();
    assert!(vault.links("Garden.md").unwrap().is_empty());
}

#[test]
fn a_link_finds_a_bud_planted_after_it_and_follows_a_rename_of_its_own_bud() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    let planted = vault.create(None, "Nowhere", Kind::Note, None).unwrap();
    assert_eq!(
        vault.links("Launch.md").unwrap()[3].to.as_deref(),
        Some(planted.as_str())
    );

    let renamed = vault.rename("Launch.md", "Launch day").unwrap();
    assert_eq!(
        vault.links(&renamed).unwrap().len(),
        4,
        "the links move with their bud"
    );
    assert!(vault.links("Launch.md").unwrap().is_empty());
}

#[test]
fn a_rescan_rebuilds_the_same_links() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    let before = vault.links("Launch.md").unwrap();
    vault.rescan().unwrap();
    assert_eq!(vault.links("Launch.md").unwrap(), before);
}

#[test]
fn trashing_hides_a_buds_links_and_restoring_brings_them_back() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    vault.trash("Launch/Welcome list.md").unwrap();
    assert!(
        vault.backlinks("Launch.md").unwrap().is_empty(),
        "its link to Launch is hidden"
    );
    assert_eq!(
        vault.links("Launch.md").unwrap()[0].to,
        None,
        "trash is never a target"
    );

    vault.trash("Kitchen.md").unwrap();
    let trashed = vault
        .roots(Place::Trash)
        .unwrap()
        .into_iter()
        .find(|b| b.title == "Kitchen")
        .unwrap()
        .path;
    assert!(vault.links(&trashed).unwrap().is_empty());
    let back = vault.restore(&trashed).unwrap();
    assert_eq!(vault.links(&back).unwrap().len(), 1);
}

#[test]
fn a_deleted_bud_leaves_no_links_behind() {
    let (mut vault, dir, _index) = vault_with(WORLD);
    std::fs::remove_file(dir.path().join("Kitchen.md")).unwrap();
    vault.rescan().unwrap();
    assert!(vault.links("Kitchen.md").unwrap().is_empty());
    assert_eq!(
        vault
            .unresolved_links()
            .unwrap()
            .into_iter()
            .map(|l| l.target)
            .collect::<Vec<_>>(),
        vec!["Nowhere".to_string()]
    );
}

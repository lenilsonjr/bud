//! Tags: what the index reads from frontmatter and bodies, and how it follows edits.

use bud_core::{Properties, State, TagCount, Vault};
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

const WORLD: &[(&str, &str)] = &[
    (
        "Groceries.md",
        "---\ntags: [home, errands]\n---\nMilk for the #Home fridge.\n",
    ),
    ("Garden.md", "Prune the roses #home #garden/roses\n"),
    (
        "Work.md",
        "---\nstate: open\ntags: work\n---\nNothing else.\n",
    ),
    (".trash/Old.md", "#home but thrown away\n"),
];

fn count(tag: &str, buds: usize) -> TagCount {
    TagCount {
        tag: tag.to_string(),
        buds,
    }
}

#[test]
fn tags_count_buds_once_in_any_case_and_leave_the_trash_out() {
    let (vault, _dir, _index) = vault_with(WORLD);
    assert_eq!(
        vault.tags().unwrap(),
        vec![
            count("home", 2),
            count("errands", 1),
            count("garden/roses", 1),
            count("work", 1)
        ]
    );
    assert_eq!(
        vault.tags_of("Groceries.md").unwrap(),
        ["home", "errands"],
        "#Home is the same tag"
    );
}

#[test]
fn tagged_finds_buds_in_any_case_and_with_a_hash() {
    let (vault, _dir, _index) = vault_with(WORLD);
    let paths = |tag: &str| {
        vault
            .tagged(tag)
            .unwrap()
            .into_iter()
            .map(|b| b.path)
            .collect::<Vec<_>>()
    };
    assert_eq!(paths("HOME"), ["Garden.md", "Groceries.md"]);
    assert_eq!(paths("#work"), ["Work.md"]);
    assert!(paths("nothing").is_empty());
    assert!(paths("").is_empty());
}

#[test]
fn writing_a_body_or_properties_keeps_the_frontmatter_tags() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    vault
        .set_body("Groceries.md", "Now also #weekly.\n")
        .unwrap();
    assert_eq!(
        vault.tags_of("Groceries.md").unwrap(),
        ["home", "errands", "weekly"]
    );

    let props = Properties {
        state: Some(State::Open),
        pinned: true,
        ..Default::default()
    };
    vault.set_properties("Work.md", &props).unwrap();
    assert_eq!(
        vault.tags_of("Work.md").unwrap(),
        ["work"],
        "an unknown key survives a write"
    );
}

#[test]
fn a_rescan_rebuilds_the_same_tags() {
    let (mut vault, _dir, _index) = vault_with(WORLD);
    let before = vault.tags().unwrap();
    vault.rescan().unwrap();
    assert_eq!(vault.tags().unwrap(), before);
}

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
    ("Garden.md", "Prune the roses #home #garden/roses #Élan\n"),
    ("Ski.md", "#élan again\n"),
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
            count("Élan", 2),
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
    assert_eq!(
        paths("ÉLAN"),
        ["Garden.md", "Ski.md"],
        "accented letters fold too"
    );
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

fn read(dir: &tempfile::TempDir, name: &str) -> String {
    std::fs::read_to_string(dir.path().join(name)).unwrap()
}

#[test]
fn adding_a_tag_keeps_the_way_the_file_writes_its_list() {
    let (mut vault, dir, _index) = vault_with(&[
        (
            "Flow.md",
            "---\nstate: open\ntags: [home, 'launch']\n---\nBody\n",
        ),
        (
            "Block.md",
            "---\ntags:\n    - home\n    - \"launch\"\nwhen: 2026-11-02\n---\nBody\n",
        ),
        ("Words.md", "---\ntags: home work\n---\n"),
        ("Commas.md", "---\ntags: home, work\n---\n"),
        ("Bare.md", "Just a body\n"),
        ("Other.md", "---\n# kept\nstate: open\n---\nBody\n"),
        ("Windows.md", "---\r\nstate: open\r\n---\r\nBody\r\n"),
    ]);
    for name in [
        "Flow.md",
        "Block.md",
        "Words.md",
        "Commas.md",
        "Bare.md",
        "Other.md",
        "Windows.md",
    ] {
        vault.add_tag(name, "#Garden").unwrap();
    }
    assert_eq!(
        read(&dir, "Flow.md"),
        "---\nstate: open\ntags: [home, 'launch', Garden]\n---\nBody\n"
    );
    assert_eq!(
        read(&dir, "Block.md"),
        "---\ntags:\n    - home\n    - \"launch\"\n    - Garden\nwhen: 2026-11-02\n---\nBody\n"
    );
    assert_eq!(read(&dir, "Words.md"), "---\ntags: home work Garden\n---\n");
    assert_eq!(
        read(&dir, "Commas.md"),
        "---\ntags: home, work, Garden\n---\n"
    );
    assert_eq!(
        read(&dir, "Bare.md"),
        "---\ntags: [Garden]\n---\nJust a body\n"
    );
    assert_eq!(
        read(&dir, "Other.md"),
        "---\n# kept\nstate: open\ntags: [Garden]\n---\nBody\n"
    );
    assert_eq!(
        read(&dir, "Windows.md"),
        "---\r\nstate: open\r\ntags: [Garden]\r\n---\r\nBody\r\n"
    );
    assert_eq!(
        vault.tags_of("Block.md").unwrap(),
        ["home", "launch", "Garden"]
    );
    assert_eq!(
        vault.bud("Flow.md").unwrap().unwrap().state,
        Some(State::Open)
    );
}

#[test]
fn adding_a_tag_a_bud_carries_in_any_case_changes_nothing() {
    let (mut vault, dir, _index) = vault_with(WORLD);
    vault.add_tag("Groceries.md", "HOME").unwrap();
    vault.add_tag("Garden.md", "garden/Roses").unwrap();
    assert_eq!(read(&dir, "Groceries.md"), WORLD[0].1);
    assert_eq!(
        read(&dir, "Garden.md"),
        WORLD[1].1,
        "a #tag in the body counts"
    );
    assert!(vault.add_tag("Garden.md", "#1").is_err(), "not a tag");
}

#[test]
fn a_number_like_tag_is_quoted_so_it_reads_back_as_text() {
    let (mut vault, dir, _index) = vault_with(&[("Note.md", "Body\n")]);
    vault.add_tag("Note.md", "1e3").unwrap();
    assert_eq!(read(&dir, "Note.md"), "---\ntags: [\"1e3\"]\n---\nBody\n");
    assert_eq!(vault.tags_of("Note.md").unwrap(), ["1e3"]);
}

#[test]
fn removing_a_tag_rewrites_the_list_and_leaves_body_tags_alone() {
    let (mut vault, dir, _index) = vault_with(&[
        (
            "Flow.md",
            "---\nstate: open\ntags: [home, errands]\n---\nMilk for the #home fridge.\n",
        ),
        ("Block.md", "---\ntags:\n- home\n- errands\n---\n"),
        ("Only.md", "---\ntags: [home]\n---\nBody\n"),
        ("Last.md", "---\nstate: open\ntags: home\n---\n"),
    ]);
    vault.remove_tag("Flow.md", "Home").unwrap();
    vault.remove_tag("Block.md", "errands").unwrap();
    vault.remove_tag("Only.md", "home").unwrap();
    vault.remove_tag("Last.md", "home").unwrap();
    assert_eq!(
        read(&dir, "Flow.md"),
        "---\nstate: open\ntags: [errands]\n---\nMilk for the #home fridge.\n"
    );
    assert_eq!(
        vault.tags_of("Flow.md").unwrap(),
        ["errands", "home"],
        "the body still says #home"
    );
    assert_eq!(read(&dir, "Block.md"), "---\ntags:\n- home\n---\n");
    assert_eq!(read(&dir, "Only.md"), "Body\n", "an empty block goes");
    assert_eq!(read(&dir, "Last.md"), "---\nstate: open\n---\n");
    vault.remove_tag("Only.md", "home").unwrap();
    assert_eq!(read(&dir, "Only.md"), "Body\n");
}

#[test]
fn renaming_a_tag_reaches_lists_bodies_and_nested_tags_outside_the_trash() {
    let (mut vault, dir, _index) = vault_with(&[
        ("Groceries.md", "---\ntags: [Home, errands]\n---\nMilk for the #home fridge, #home/kitchen, not #homely or `#home`.\n"),
        ("Plain.md", "#HOME first\n"),
        ("Away.md", "Nothing here\n"),
        (".trash/Old.md", "#home but thrown away\n"),
    ]);
    let edits = vault.rename_tag("home", "house").unwrap();
    assert_eq!(
        edits.iter().map(|e| e.path.as_str()).collect::<Vec<_>>(),
        ["Groceries.md", "Plain.md"]
    );
    assert_eq!(
        read(&dir, "Groceries.md"),
        "---\ntags: [house, errands]\n---\nMilk for the #house fridge, #house/kitchen, not #homely or `#home`.\n"
    );
    assert_eq!(read(&dir, "Plain.md"), "#house first\n");
    assert_eq!(read(&dir, ".trash/Old.md"), "#home but thrown away\n");
    assert!(vault.tagged("home").unwrap().is_empty());
    assert_eq!(
        vault.tags_of("Groceries.md").unwrap(),
        ["house", "errands", "house/kitchen", "homely"]
    );
    assert_eq!(edits[1].before, "#HOME first\n");
    assert_eq!(edits[1].after, "#house first\n");
}

#[test]
fn renaming_onto_a_tag_in_use_merges_them_and_undo_puts_the_text_back() {
    let (mut vault, dir, _index) = vault_with(&[(
        "Groceries.md",
        "---\ntags:\n  - errands\n  - home\n  - chores\n---\n#errands today\n",
    )]);
    let edits = vault.rename_tag("errands", "chores").unwrap();
    assert_eq!(
        read(&dir, "Groceries.md"),
        "---\ntags:\n  - chores\n  - home\n---\n#chores today\n"
    );
    assert_eq!(
        vault.tags().unwrap(),
        vec![count("chores", 1), count("home", 1)]
    );
    for edit in &edits {
        vault.set_text(&edit.path, &edit.before).unwrap();
    }
    assert_eq!(
        read(&dir, "Groceries.md"),
        "---\ntags:\n  - errands\n  - home\n  - chores\n---\n#errands today\n"
    );
    assert_eq!(
        vault.tags_of("Groceries.md").unwrap(),
        ["errands", "home", "chores"]
    );
}

#[test]
fn renaming_only_the_case_of_a_tag_rewrites_it() {
    let (mut vault, dir, _index) = vault_with(&[("Note.md", "---\ntags: [home]\n---\n#home\n")]);
    vault.rename_tag("home", "Home").unwrap();
    assert_eq!(read(&dir, "Note.md"), "---\ntags: [Home]\n---\n#Home\n");
    assert!(vault.rename_tag("home", "no way").is_err());
}

/// Each way a file can write its list that an edit must not break, with the text it gives back.
#[test]
fn awkward_lists_are_rewritten_without_breaking_the_block() {
    let cases: &[(&str, &str, &str, &str)] = &[
        // (file, change, tag, expected)
        (
            "---\nstate: open\ntags: # mine\n- a\n- b\n---\n",
            "add",
            "c",
            "---\nstate: open\ntags: # mine\n- a\n- b\n- c\n---\n",
        ),
        (
            "---\ntags: [a,\n  b]\nstate: open\n---\n",
            "add",
            "c",
            "---\ntags: [a, b, c]\nstate: open\n---\n",
        ),
        (
            "---\ntags : [a]\n---\n",
            "add",
            "b",
            "---\ntags: [a, b]\n---\n",
        ),
        (
            "---\ntags: a, b # note\n---\n",
            "remove",
            "a",
            "---\ntags: b # note\n---\n",
        ),
        (
            "---\ntags:\n  - a # x\n  - b\n---\n",
            "remove",
            "a",
            "---\ntags:\n  - b\n---\n",
        ),
        (
            "---\ntitle: t\ntags:\n  - a\n\n  - b\n---\n",
            "remove",
            "a",
            "---\ntitle: t\ntags:\n  - b\n---\n",
        ),
        (
            "---\ntags:\n  - a\n\n  - b\n---\n",
            "remove",
            "b",
            "---\ntags:\n  - a\n---\n",
        ),
        (
            "---\ntags: [a]\n---\n---\nhr\n---\n",
            "remove",
            "a",
            "---\n---\n---\nhr\n---\n",
        ),
        (
            "---\ntags: a, 2024, b\n---\n",
            "remove",
            "a",
            "---\ntags: 2024, b\n---\n",
        ),
        (
            "---\ntags: [\"a,b\", c]\n---\n",
            "remove",
            "c",
            "---\ntags: [\"a,b\"]\n---\n",
        ),
        (
            "---\ntags: [a, b] # c\n---\n",
            "remove",
            "a",
            "---\ntags: [b] # c\n---\n",
        ),
    ];
    for (file, change, tag, want) in cases {
        let (mut vault, dir, _index) = vault_with(&[("Note.md", file)]);
        match *change {
            "add" => vault.add_tag("Note.md", tag).unwrap(),
            _ => vault.remove_tag("Note.md", tag).unwrap(),
        }
        assert_eq!(&read(&dir, "Note.md"), want, "{change} {tag} on {file:?}");
    }
}

#[test]
fn a_rename_keeps_repeats_it_did_not_make_and_quotes_words_that_need_it() {
    let (mut vault, dir, _index) = vault_with(&[
        ("Repeats.md", "---\ntags: [a, A, b]\n---\n"),
        ("Words.md", "---\nstate: open\ntags: home\n---\n"),
    ]);
    vault.rename_tag("b", "c").unwrap();
    assert_eq!(read(&dir, "Repeats.md"), "---\ntags: [a, A, c]\n---\n");
    vault.rename_tag("home", "true").unwrap();
    assert_eq!(
        read(&dir, "Words.md"),
        "---\nstate: open\ntags: [\"true\"]\n---\n"
    );
    assert_eq!(vault.tags_of("Words.md").unwrap(), ["true"]);
}

#[test]
fn a_list_bud_cannot_rewrite_safely_is_refused_and_left_alone() {
    let file = "---\nbase: &t [a, b]\ntags: *t\n---\n";
    let (mut vault, dir, _index) = vault_with(&[("Note.md", file)]);
    assert!(vault.add_tag("Note.md", "c").is_err());
    assert_eq!(read(&dir, "Note.md"), file);
    assert!(vault.rename_tag("a", "z").unwrap().is_empty());
    assert_eq!(read(&dir, "Note.md"), file);
}

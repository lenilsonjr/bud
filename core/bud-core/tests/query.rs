//! The queries behind search, Today, the counts, the Next step pill and the lenses.

use bud_core::{Counts, Kind, Lens, Properties, State, Vault};
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

fn paths(rows: &[bud_core::Row]) -> Vec<&str> {
    rows.iter().map(|r| r.bud.path.as_str()).collect()
}

const WORLD: &[(&str, &str)] = &[
    ("Launch.md", "---\ncreated: 2026-10-01T09:00:00Z\n---\nThe launch plan.\n"),
    (
        "Launch/Welcome list.md",
        "---\ncreated: 2026-10-02T09:00:00Z\n---\nWho gets the first issue.\n",
    ),
    (
        "Launch/Write the welcome issue.md",
        "---\nstate: open\ndue: 2026-11-05\ncreated: 2026-10-03T09:00:00Z\n---\nDraft the listing of links.\n",
    ),
    (
        "Inbox/Listen to the podcast.md",
        "---\ncreated: 2026-10-04T09:00:00Z\n---\nA note on the welcome series.\n",
    ),
    (
        ".trash/Old list.md",
        "---\ncreated: 2026-09-01T09:00:00Z\n---\nA discarded list.\n",
    ),
];

#[test]
fn search_matches_a_prefix_on_the_last_token() {
    let (vault, _d, _i) = vault_with(WORLD);
    let hits = vault.search("lis", 10).unwrap();
    let found: Vec<&str> = hits.iter().map(|h| h.path.as_str()).collect();
    assert_eq!(
        found,
        vec![
            "Launch/Welcome list.md",
            "Inbox/Listen to the podcast.md",
            "Launch/Write the welcome issue.md",
        ],
        "title hits first, Inbox included, Trash left out, body hit last"
    );
    let first = &hits[0];
    assert_eq!(first.title, "Welcome list");
    assert_eq!(first.trail, vec!["Launch".to_string()]);
    assert!(hits[2].snippet.contains("listing"), "{:?}", hits[2].snippet);
}

#[test]
fn search_with_two_words_needs_both() {
    let (vault, _d, _i) = vault_with(WORLD);
    let hits = vault.search("welcome lis", 10).unwrap();
    let mut found: Vec<&str> = hits.iter().map(|h| h.path.as_str()).collect();
    assert_eq!(found[0], "Launch/Welcome list.md", "the title hit is first");
    found.sort();
    assert_eq!(
        found,
        vec![
            "Inbox/Listen to the podcast.md",
            "Launch/Welcome list.md",
            "Launch/Write the welcome issue.md"
        ],
        "each word may match in the title or the body"
    );
    assert!(vault.search("welcome zebra", 10).unwrap().is_empty());
}

#[test]
fn search_respects_the_limit_and_odd_input() {
    let (vault, _d, _i) = vault_with(WORLD);
    assert_eq!(vault.search("lis", 1).unwrap().len(), 1);
    assert!(vault.search("", 10).unwrap().is_empty());
    assert!(vault.search("  \"*() ", 10).unwrap().is_empty());
    assert!(vault.search("lis", 0).unwrap().is_empty());
    // FTS syntax in the query is plain text.
    assert!(vault.search("lis AND OR NEAR(", 10).is_ok());
}

#[test]
fn search_follows_every_write() {
    let (mut vault, _d, _i) = vault_with(WORLD);
    let path = vault
        .create(None, "Zebra stripes", Kind::Note, None)
        .unwrap();
    assert_eq!(vault.search("zebr", 10).unwrap().len(), 1);

    vault.set_body(&path, "Quokka facts.\n").unwrap();
    assert_eq!(vault.search("quok", 10).unwrap().len(), 1);

    let renamed = vault.rename(&path, "Okapi stripes").unwrap();
    assert!(vault.search("zebr", 10).unwrap().is_empty());
    assert_eq!(vault.search("okap", 10).unwrap()[0].path, renamed);

    vault.trash(&renamed).unwrap();
    assert!(vault.search("okap", 10).unwrap().is_empty());
    assert!(vault.search("quok", 10).unwrap().is_empty());

    let restored = vault.restore(&format!(".trash/{renamed}")).unwrap();
    assert_eq!(vault.search("okap", 10).unwrap()[0].path, restored);
}

#[test]
fn search_follows_a_rescan_of_edited_and_removed_files() {
    let (mut vault, dir, _i) = vault_with(WORLD);
    std::fs::remove_file(dir.path().join("Launch/Welcome list.md")).unwrap();
    std::fs::write(
        dir.path().join("Launch.md"),
        "---\ncreated: 2026-10-01T09:00:00Z\n---\nThe heron plan.\n",
    )
    .unwrap();
    // A different size is not needed: bump the mtime so the scan reads it again.
    let later = std::time::SystemTime::now() + std::time::Duration::from_secs(60);
    std::fs::File::options()
        .write(true)
        .open(dir.path().join("Launch.md"))
        .unwrap()
        .set_modified(later)
        .unwrap();
    vault.rescan().unwrap();
    assert!(vault
        .search("welcome lis", 10)
        .unwrap()
        .iter()
        .all(|h| h.path != "Launch/Welcome list.md"));
    assert_eq!(vault.search("heron", 10).unwrap().len(), 1);
    assert!(vault.search("heron", 10).unwrap()[0]
        .snippet
        .contains("heron"));
}

const TODOS: &[(&str, &str)] = &[
    (
        "Overdue.md",
        "---\nstate: open\ndue: 2026-10-30\ncreated: 2026-10-01T00:00:00Z\n---\n",
    ),
    (
        "Due today.md",
        "---\nstate: open\ndue: 2026-11-02\nwhen: 2026-10-01\ncreated: 2026-10-02T00:00:00Z\n---\n",
    ),
    (
        "Due later.md",
        "---\nstate: open\ndue: 2026-11-09\ncreated: 2026-10-03T00:00:00Z\n---\n",
    ),
    (
        "Start old.md",
        "---\nstate: open\nwhen: 2026-10-20\ncreated: 2026-10-04T00:00:00Z\n---\n",
    ),
    (
        "Start today.md",
        "---\nstate: open\nwhen: 2026-11-02\ncreated: 2026-10-05T00:00:00Z\n---\n",
    ),
    (
        "Start later.md",
        "---\nstate: open\nwhen: 2026-11-03\ncreated: 2026-10-06T00:00:00Z\n---\n",
    ),
    (
        "Finished.md",
        "---\nstate: done\ndue: 2026-10-29\ncreated: 2026-10-07T00:00:00Z\n---\n",
    ),
    (
        "A note.md",
        "---\ndue: 2026-10-29\ncreated: 2026-10-08T00:00:00Z\n---\n",
    ),
    (
        ".trash/Binned.md",
        "---\nstate: open\ndue: 2026-10-29\ncreated: 2026-10-09T00:00:00Z\n---\n",
    ),
    (
        "Thread/Deep.md",
        "---\nstate: open\ndue: 2026-10-31\ncreated: 2026-10-10T00:00:00Z\n---\n",
    ),
];

#[test]
fn today_lists_due_first_then_when() {
    let (vault, _d, _i) = vault_with(TODOS);
    let rows = vault.today("2026-11-02").unwrap();
    assert_eq!(
        paths(&rows),
        vec![
            "Overdue.md",
            "Thread/Deep.md",
            "Due today.md",
            "Start old.md",
            "Start today.md"
        ]
    );
    let deep = &rows[1];
    assert_eq!(deep.trail, vec!["Thread".to_string()]);
    assert!(rows[0].trail.is_empty());
}

#[test]
fn today_before_everything_is_empty() {
    let (vault, _d, _i) = vault_with(TODOS);
    assert!(vault.today("2026-01-01").unwrap().is_empty());
}

const TREE: &[(&str, &str)] = &[
    ("Top.md", "---\ncreated: 2026-10-01T00:00:00Z\n---\n"),
    ("Top/Mid.md", "---\ncreated: 2026-10-01T00:00:00Z\n---\n"),
    ("Top/Mid/Leaf one.md", "---\nstate: open\n---\n"),
    ("Top/Mid/Leaf two.md", "---\nstate: done\n---\n"),
    ("Top/Side.md", "---\nstate: open\n---\n"),
    ("Top/Folder only/Deep.md", "---\nstate: open\n---\n"),
    ("Other.md", "---\nstate: open\n---\n"),
];

#[test]
fn counts_cover_all_descendants_of_a_three_level_tree() {
    let (vault, _d, _i) = vault_with(TREE);
    assert_eq!(
        vault.counts("Top.md").unwrap(),
        Counts {
            inside: 6,
            open_todos: 3
        }
    );
    assert_eq!(
        vault.counts("Top/Mid.md").unwrap(),
        Counts {
            inside: 2,
            open_todos: 1
        }
    );
    assert_eq!(
        vault.counts("Top/Folder only").unwrap(),
        Counts {
            inside: 1,
            open_todos: 1
        }
    );
    assert_eq!(
        vault.counts("Other.md").unwrap(),
        Counts {
            inside: 0,
            open_todos: 0
        }
    );
}

fn todo(name: &str, props: &str) -> (String, String) {
    (name.to_string(), format!("---\nstate: open\n{props}---\n"))
}

fn next_in(files: &[(String, String)], under: Option<&str>) -> Option<String> {
    let refs: Vec<(&str, &str)> = files
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    let (vault, _d, _i) = vault_with(&refs);
    vault
        .next_step(under, "2026-11-02")
        .unwrap()
        .map(|r| r.bud.path)
}

#[test]
fn next_step_orders_by_due() {
    let files = vec![
        todo("Late.md", "due: 2026-11-09\n"),
        todo("Soon.md", "due: 2026-11-03\n"),
        todo("Timed.md", "when: 2026-10-01\n"),
    ];
    assert_eq!(next_in(&files, None).as_deref(), Some("Soon.md"));
}

#[test]
fn next_step_orders_by_when_without_due() {
    let files = vec![
        todo(
            "Later.md",
            "when: 2026-11-09\ncreated: 2026-10-01T00:00:00Z\n",
        ),
        todo(
            "Sooner.md",
            "when: 2026-11-03\ncreated: 2026-10-02T00:00:00Z\n",
        ),
        todo("Plain.md", "created: 2026-09-01T00:00:00Z\n"),
    ];
    assert_eq!(next_in(&files, None).as_deref(), Some("Sooner.md"));
}

#[test]
fn next_step_falls_back_to_the_oldest_created() {
    let files = vec![
        todo("Newer.md", "created: 2026-10-05T00:00:00Z\n"),
        todo("Older.md", "created: 2026-10-01T00:00:00Z\n"),
        todo("Undated.md", ""),
    ];
    assert_eq!(next_in(&files, None).as_deref(), Some("Older.md"));
}

#[test]
fn next_step_breaks_a_due_tie_by_when_then_created() {
    let files = vec![
        todo(
            "A.md",
            "due: 2026-11-03\nwhen: 2026-11-02\ncreated: 2026-10-01T00:00:00Z\n",
        ),
        todo(
            "B.md",
            "due: 2026-11-03\nwhen: 2026-11-01\ncreated: 2026-10-05T00:00:00Z\n",
        ),
        todo(
            "C.md",
            "due: 2026-11-03\nwhen: 2026-11-01\ncreated: 2026-10-02T00:00:00Z\n",
        ),
    ];
    assert_eq!(next_in(&files, None).as_deref(), Some("C.md"));
}

#[test]
fn next_step_stays_under_the_bud_and_skips_done_notes_and_trash() {
    let mut files = vec![
        ("Top.md".to_string(), String::new()),
        todo("Top/Inside.md", "due: 2026-12-01\n"),
        todo("Elsewhere.md", "due: 2026-11-01\n"),
        todo(".trash/Binned.md", "due: 2026-10-01\n"),
        (
            "Top/Done.md".to_string(),
            "---\nstate: done\ndue: 2026-10-01\n---\n".to_string(),
        ),
        (
            "Top/Note.md".to_string(),
            "---\ndue: 2026-10-01\n---\n".to_string(),
        ),
    ];
    assert_eq!(
        next_in(&files, Some("Top.md")).as_deref(),
        Some("Top/Inside.md")
    );
    assert_eq!(next_in(&files, None).as_deref(), Some("Elsewhere.md"));
    files.retain(|(n, _)| !n.starts_with("Top/Inside") && n != "Elsewhere.md");
    assert_eq!(next_in(&files, Some("Top.md")), None);
}

#[test]
fn lenses_list_open_todos_and_pinned_buds_with_trails() {
    let (mut vault, _d, _i) = vault_with(TODOS);
    let todos = vault.lens(Lens::Todos).unwrap();
    assert_eq!(
        paths(&todos),
        vec![
            "Overdue.md",
            "Thread/Deep.md",
            "Due today.md",
            "Due later.md",
            "Start old.md",
            "Start today.md",
            "Start later.md"
        ]
    );
    assert_eq!(todos[1].trail, vec!["Thread".to_string()]);

    assert!(vault.lens(Lens::Pinned).unwrap().is_empty());
    vault
        .set_properties(
            "Thread/Deep.md",
            &Properties {
                state: Some(State::Open),
                pinned: true,
                ..Default::default()
            },
        )
        .unwrap();
    vault.set_pinned("A note.md", true).unwrap();
    vault.set_pinned(".trash/Binned.md", true).unwrap();
    let pinned = vault.lens(Lens::Pinned).unwrap();
    let mut found = paths(&pinned);
    found.sort();
    assert_eq!(found, vec!["A note.md", "Thread/Deep.md"]);
    let deep = pinned
        .iter()
        .find(|r| r.bud.path == "Thread/Deep.md")
        .unwrap();
    assert_eq!(deep.trail, vec!["Thread".to_string()]);
}

/// Five thousand generated buds, three levels deep. Run it with
/// `cargo test --release -p bud-core --test query -- --ignored --nocapture`.
#[test]
#[ignore]
fn each_query_runs_under_20_ms_on_5000_buds() {
    let dir = tempfile::tempdir().unwrap();
    let words = [
        "brand", "launch", "issue", "list", "sender", "draft", "link",
    ];
    let mut n = 0;
    'outer: for a in 0..10 {
        for b in 0..10 {
            for c in 0..50 {
                if n == 5000 {
                    break 'outer;
                }
                let w = words[n % words.len()];
                let folder = dir.path().join(format!("Thread {a}/Topic {b}"));
                std::fs::create_dir_all(&folder).unwrap();
                let day = 1 + n % 28;
                let state = if n % 3 == 0 { "state: open\n" } else { "" };
                let due = if n % 5 == 0 {
                    format!("due: 2026-11-{day:02}\n")
                } else {
                    String::new()
                };
                let pinned = if n % 50 == 0 { "pinned: true\n" } else { "" };
                std::fs::write(
                    folder.join(format!("Item {c} {w}.md")),
                    format!(
                        "---\n{state}{due}{pinned}created: 2026-10-{day:02}T00:00:00Z\n---\nBody about the {w} and more.\n"
                    ),
                )
                .unwrap();
                n += 1;
            }
        }
    }
    let index = tempfile::tempdir().unwrap();
    let mut vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    vault.rescan().unwrap();

    fn timed<T>(name: &str, run: impl Fn() -> T) {
        run();
        let start = std::time::Instant::now();
        run();
        let took = start.elapsed();
        println!("{name}: {took:?}");
        assert!(took.as_millis() < 20, "{name} took {took:?}");
    }
    timed("search lis", || vault.search("lis", 50).unwrap());
    timed("search two words", || {
        vault.search("item list", 50).unwrap()
    });
    timed("today", || vault.today("2026-11-15").unwrap());
    timed("counts", || vault.counts("Thread 3").unwrap());
    timed("next_step vault", || {
        vault.next_step(None, "2026-11-15").unwrap()
    });
    timed("next_step under", || {
        vault.next_step(Some("Thread 3"), "2026-11-15").unwrap()
    });
    timed("lens todos", || vault.lens(Lens::Todos).unwrap());
    timed("lens pinned", || vault.lens(Lens::Pinned).unwrap());
}

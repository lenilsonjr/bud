//! The sync module: one document per bud, reconciled with the Markdown file. Two replicas are two
//! copies of the fixture vault, each with its own index; documents travel as bytes.

mod common;

use bud_core::Vault;
use common::{fingerprint, fixture, pair, send_doc, Replica};
use pretty_assertions::assert_eq;
use std::collections::BTreeMap;

#[test]
fn the_first_sync_makes_a_document_for_every_bud() {
    let mut replica = Replica::new();
    let report = replica.vault.sync().unwrap();
    assert_eq!(report.created, 13);
    assert_eq!(report.written, 0);
    for bud in replica.vault.all().unwrap() {
        assert!(
            replica.vault.doc_id(&bud.path).unwrap().is_some(),
            "{}",
            bud.path
        );
    }
    let text = replica.read("Gift ideas.md");
    let (_, body) = bud_core::split_frontmatter(&text);
    assert_eq!(
        replica.vault.doc_text("Gift ideas.md").unwrap().as_deref(),
        Some(body)
    );
    let again = replica.vault.sync().unwrap();
    assert_eq!(
        (again.created, again.updated, again.written, again.ops),
        (0, 0, 0, 0)
    );
}

#[test]
fn a_scan_and_a_sync_never_write_the_vault() {
    let before = fingerprint(&fixture());
    let index = tempfile::tempdir().unwrap();
    let mut vault = Vault::open(fixture(), index.path().join("index.db")).unwrap();
    vault.rescan().unwrap();
    vault.sync().unwrap();
    vault.rescan().unwrap();
    vault.sync().unwrap();
    assert_eq!(fingerprint(&fixture()), before);
}

#[test]
fn an_outside_edit_becomes_operations_and_no_file_write() {
    let mut replica = Replica::new();
    replica.vault.sync().unwrap();
    let edited = "---\nstate: done\ndue: 2026-11-09\n---\nWarm, not corporate.\nAnd brief.\n";
    replica.write("Launch the newsletter/Design notes.md", edited);
    let mtime = std::fs::metadata(
        replica
            .dir
            .path()
            .join("Launch the newsletter/Design notes.md"),
    )
    .unwrap()
    .modified()
    .unwrap();
    let report = replica.rescan_and_sync();
    assert_eq!(report.updated, 1);
    assert!(report.ops > 0);
    assert_eq!(report.written, 0);
    assert_eq!(
        replica.read("Launch the newsletter/Design notes.md"),
        edited
    );
    assert_eq!(
        std::fs::metadata(
            replica
                .dir
                .path()
                .join("Launch the newsletter/Design notes.md")
        )
        .unwrap()
        .modified()
        .unwrap(),
        mtime
    );
    assert_eq!(
        replica
            .vault
            .doc_text("Launch the newsletter/Design notes.md")
            .unwrap()
            .as_deref(),
        Some("Warm, not corporate.\nAnd brief.\n")
    );
    // Properties are map sets: the document now writes back what the file says, so nothing more.
    let again = replica.rescan_and_sync();
    assert_eq!((again.ops, again.written), (0, 0));
}

#[test]
fn two_documents_edited_apart_merge_to_one_text_with_both_edits() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Design notes.md";
    a.write(path, "## Voice\n\nWarm, not corporate.\nShort sentences.\n");
    b.write(path, "## Tone and voice\n\nWarm, not corporate.\n");
    a.rescan_and_sync();
    b.rescan_and_sync();

    let a_to_b = send_doc(&a, &mut b, path);
    assert_eq!(a_to_b.written, 1);
    let b_to_a = send_doc(&b, &mut a, path);
    assert_eq!(b_to_a.written, 1);

    let merged = "## Tone and voice\n\nWarm, not corporate.\nShort sentences.\n";
    assert_eq!(a.read(path), merged);
    assert_eq!(b.read(path), merged);

    // Merging what is already merged writes nothing.
    let again = send_doc(&a, &mut b, path);
    assert_eq!(again.written, 0);
    let again = send_doc(&b, &mut a, path);
    assert_eq!(again.written, 0);
}

#[test]
fn an_outside_edit_not_yet_synced_survives_a_merge_of_remote_edits() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Design notes.md";
    b.write(
        path,
        "---\ndue: 2026-11-09\n---\n## Tone and voice\n\nWarm, not corporate.\n",
    );
    b.rescan_and_sync();
    // A's file is edited outside, and no sync runs before B's document arrives.
    a.write(path, "## Voice\n\nWarm, not corporate.\nShort sentences.\n");
    send_doc(&b, &mut a, path);

    let merged =
        "---\ndue: 2026-11-09\n---\n## Tone and voice\n\nWarm, not corporate.\nShort sentences.\n";
    assert_eq!(a.read(path), merged);
    a.rescan_and_sync();
    send_doc(&a, &mut b, path);
    assert_eq!(b.read(path), merged);
    assert_eq!(a.rescan_and_sync().written, 0);
}

#[test]
fn a_property_set_on_one_replica_reaches_the_file_of_the_other() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Set up the sender.md";
    let text = a.read(path);
    a.write(path, &text.replacen("state: open", "state: done", 1));
    a.rescan_and_sync();
    send_doc(&a, &mut b, path);
    assert!(b.read(path).contains("state: done"));
    // Only the key line changed.
    assert_eq!(b.read(path), a.read(path));
}

#[test]
fn a_rename_on_one_replica_and_an_edit_on_the_other_end_with_the_edit_under_the_new_name() {
    let (mut a, mut b) = pair();
    let old = "Gift ideas.md";
    let new = "Present ideas.md";
    let id = a.vault.doc_id(old).unwrap().unwrap();

    a.vault.rename(old, "Present ideas").unwrap();
    a.vault.sync().unwrap();

    let original = b.read(old);
    b.write(old, &format!("{original}A scarf.\n"));
    b.rescan_and_sync();

    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(!b.exists(old));
    assert_eq!(b.vault.doc_id(new).unwrap().as_deref(), Some(id.as_str()));
    send_doc(&b, &mut a, new);

    assert!(!a.exists(old));
    assert!(a.read(new).ends_with("A scarf.\n"));
    assert_eq!(a.read(new), b.read(new));
}

#[test]
fn two_replicas_that_move_the_same_bud_converge() {
    let (mut a, mut b) = pair();
    let moved = "Gift ideas.md";
    a.vault
        .move_to(moved, Some("Launch the newsletter.md"))
        .unwrap();
    b.vault.move_to(moved, Some("Routines")).unwrap();
    a.vault.sync().unwrap();
    b.vault.sync().unwrap();

    let a_tree = a.vault.tree_bytes().unwrap();
    let b_tree = b.vault.tree_bytes().unwrap();
    a.vault.merge_tree(&b_tree).unwrap();
    b.vault.merge_tree(&a_tree).unwrap();

    let in_a = a
        .vault
        .doc_id("Launch the newsletter/Gift ideas.md")
        .unwrap();
    let in_b = b
        .vault
        .doc_id("Launch the newsletter/Gift ideas.md")
        .unwrap();
    let routines_a = a.vault.doc_id("Routines/Gift ideas.md").unwrap();
    let routines_b = b.vault.doc_id("Routines/Gift ideas.md").unwrap();
    assert_eq!(in_a.is_some(), in_b.is_some());
    assert_eq!(routines_a.is_some(), routines_b.is_some());
    assert!(in_a.is_some() != routines_a.is_some(), "one place, not two");
    assert!(!a.exists("Gift ideas.md") && !b.exists("Gift ideas.md"));
    assert_eq!(fingerprint_no_trash(&a), fingerprint_no_trash(&b));
}

fn fingerprint_no_trash(replica: &Replica) -> BTreeMap<String, u64> {
    fingerprint(replica.dir.path())
}

#[test]
fn trashing_and_restoring_travel_through_the_tree() {
    let (mut a, mut b) = pair();
    a.vault.trash("Gift ideas.md").unwrap();
    a.vault.sync().unwrap();
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(!b.exists("Gift ideas.md"));
    assert!(b.exists(".trash/Gift ideas.md"));

    let restored = a.vault.restore(".trash/Gift ideas.md").unwrap();
    assert_eq!(restored, "Gift ideas.md");
    a.vault.sync().unwrap();
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert!(b.exists("Gift ideas.md"));
    assert!(!b.exists(".trash/Gift ideas.md"));
}

#[test]
fn merging_a_tree_that_matches_the_folder_writes_nothing() {
    let (a, mut b) = pair();
    let before = fingerprint(b.dir.path());
    let report = b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    assert_eq!((report.moved, report.written), (0, 0));
    assert_eq!(fingerprint(b.dir.path()), before);
}

#[test]
fn a_file_that_goes_leaves_no_document() {
    let mut replica = Replica::new();
    replica.vault.sync().unwrap();
    std::fs::remove_file(replica.dir.path().join("Gift ideas.md")).unwrap();
    replica.rescan_and_sync();
    assert_eq!(replica.vault.doc_id("Gift ideas.md").unwrap(), None);
}

/// Trash `path` on `a` and let `b` follow.
fn trash_on_both(a: &mut Replica, b: &mut Replica, path: &str) -> String {
    a.vault.trash(path).unwrap();
    a.vault.sync().unwrap();
    b.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    b.vault.sync().unwrap();
    format!(".trash/{path}")
}

fn exchange(a: &mut Replica, b: &mut Replica) {
    for _ in 0..2 {
        let to_b = a.vault.updates_for(&b.vault.heads().unwrap()).unwrap();
        b.vault.apply_updates(&to_b).unwrap();
        b.vault.sync().unwrap();
        let to_a = b.vault.updates_for(&a.vault.heads().unwrap()).unwrap();
        a.vault.apply_updates(&to_a).unwrap();
        a.vault.sync().unwrap();
    }
}

#[test]
fn deleting_forever_reaches_the_peer_and_nothing_comes_back() {
    let (mut a, mut b) = pair();
    let trashed = trash_on_both(&mut a, &mut b, "Gift ideas.md");
    assert!(b.exists(&trashed));

    a.vault.delete_forever(&trashed).unwrap();
    a.vault.sync().unwrap();
    exchange(&mut a, &mut b);

    assert!(!b.exists(&trashed));
    assert!(b.vault.bud(&trashed).unwrap().is_none());
    assert_eq!(b.vault.doc_id(&trashed).unwrap(), None);
    assert!(b.vault.restore(&trashed).is_err());
    b.rescan_and_sync();
    exchange(&mut a, &mut b);
    for replica in [&a, &b] {
        assert!(!replica.exists(&trashed) && !replica.exists("Gift ideas.md"));
    }
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn deleting_forever_a_bud_with_children_reaches_the_peer() {
    let (mut a, mut b) = pair();
    let trashed = trash_on_both(&mut a, &mut b, "Launch the newsletter.md");
    a.vault.delete_forever(&trashed).unwrap();
    a.vault.sync().unwrap();
    exchange(&mut a, &mut b);

    for replica in [&a, &b] {
        assert!(!replica.exists(".trash/Launch the newsletter.md"));
        assert!(!replica.exists(".trash/Launch the newsletter"));
        assert!(!replica.exists("Launch the newsletter.md"));
        let left = replica.vault.all().unwrap();
        assert!(left
            .iter()
            .all(|bud| !bud.path.contains("Launch the newsletter")));
    }
    assert_eq!(
        b.vault
            .doc_id(".trash/Launch the newsletter/Pick a name.md")
            .unwrap(),
        None
    );
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn a_bud_restored_while_a_peer_deletes_it_forever_is_kept_under_a_new_identity() {
    let (mut a, mut b) = pair();
    let trashed = trash_on_both(&mut a, &mut b, "Gift ideas.md");
    let old_id = b.vault.doc_id(&trashed).unwrap().unwrap();
    a.vault.delete_forever(&trashed).unwrap();
    a.vault.sync().unwrap();
    b.vault.restore(&trashed).unwrap();
    b.vault.sync().unwrap();
    exchange(&mut a, &mut b);

    let kept = b.vault.doc_id("Gift ideas.md").unwrap().unwrap();
    assert_ne!(kept, old_id);
    assert_eq!(a.vault.doc_id("Gift ideas.md").unwrap(), Some(kept));
    assert_eq!(a.read("Gift ideas.md"), b.read("Gift ideas.md"));
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn a_folder_bud_that_gets_its_file_from_an_edit_stays_one_bud_on_the_peer() {
    let (mut a, mut b) = pair();
    let id = a
        .vault
        .doc_id("Routines")
        .unwrap()
        .expect("the folder has a document");
    a.vault.set_pinned("Routines", true).unwrap();
    a.vault.add_tag("Routines.md", "home").unwrap();
    assert_eq!(
        a.vault.doc_id("Routines.md").unwrap(),
        Some(id.clone()),
        "the document follows the file"
    );
    assert_eq!(a.vault.doc_id("Routines").unwrap(), None);

    a.vault.sync().unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(b.vault.doc_id("Routines.md").unwrap(), Some(id));
    assert!(b.read("Routines.md").contains("pinned: true"));
    let named = |r: &Replica| {
        r.vault
            .all()
            .unwrap()
            .into_iter()
            .filter(|bud| bud.title.starts_with("Routines"))
            .count()
    };
    assert_eq!(named(&a), 1);
    assert_eq!(named(&b), 1);
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn a_body_written_to_a_folder_bud_reaches_the_peer_as_its_file() {
    let (mut a, mut b) = pair();
    let id = a
        .vault
        .doc_id("Routines")
        .unwrap()
        .expect("the folder has a document");
    a.vault.set_body("Routines", "Hello body\n").unwrap();
    a.vault.sync().unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(b.vault.doc_id("Routines.md").unwrap(), Some(id));
    assert!(b.read("Routines.md").contains("Hello body"));
    assert_eq!(
        a.vault.doc_text("Routines.md").unwrap(),
        b.vault.doc_text("Routines.md").unwrap()
    );
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
    assert_eq!(b.rescan_and_sync().written, 0);
}

#[test]
fn a_file_written_outside_beside_a_folder_bud_keeps_the_bud_whole_on_both_devices() {
    let (mut a, mut b) = pair();
    let id = a
        .vault
        .doc_id("Routines")
        .unwrap()
        .expect("the folder has a document");
    let child = "Routines/Weekly review.md";
    let child_id = a.vault.doc_id(child).unwrap();
    let text = "---\npinned: true\n---\nWritten elsewhere\n";
    a.write("Routines.md", text);
    assert_eq!(a.rescan_and_sync().created, 0, "no new bud");
    assert_eq!(
        a.vault.doc_id("Routines.md").unwrap(),
        Some(id.clone()),
        "the same bud at its file"
    );
    exchange(&mut a, &mut b);
    assert_eq!(b.vault.doc_id("Routines.md").unwrap(), Some(id));
    assert_eq!(b.read("Routines.md"), text);
    for replica in [&a, &b] {
        assert_eq!(replica.vault.doc_id(child).unwrap(), child_id);
        assert_eq!(
            replica.vault.bud(child).unwrap().unwrap().parent.as_deref(),
            Some("Routines.md")
        );
        assert_eq!(replica.vault.pending_changes().unwrap(), 0);
    }
    let again = a.rescan_and_sync();
    assert_eq!((again.updated, again.written, again.ops), (0, 0, 0));
    let named = |r: &Replica| {
        r.vault
            .all()
            .unwrap()
            .into_iter()
            .filter(|bud| bud.title.starts_with("Routines"))
            .count()
    };
    assert_eq!(named(&a), 1);
    assert_eq!(named(&b), 1);
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

/// A third replica that shares the identities of `a`.
fn join(a: &mut Replica) -> Replica {
    let mut c = Replica::new();
    for bud in c.vault.all().unwrap() {
        if bud.place == bud_core::Place::Trash && !bud.path.ends_with(".md") {
            continue;
        }
        let id = a.vault.doc_id(&bud.path).unwrap().unwrap();
        let bytes = a.vault.doc_bytes(&bud.path).unwrap().unwrap();
        c.vault.adopt_doc(&bud.path, &id, &bytes).unwrap();
    }
    c.vault.merge_tree(&a.vault.tree_bytes().unwrap()).unwrap();
    c.vault.sync().unwrap();
    c
}

/// What `from` has that `to` lacks, one way.
fn send(from: &Replica, to: &mut Replica) {
    let updates = from.vault.updates_for(&to.vault.heads().unwrap()).unwrap();
    to.vault.apply_updates(&updates).unwrap();
    to.vault.sync().unwrap();
}

#[test]
fn a_bud_two_devices_restored_while_a_third_deletes_it_forever_stays_one_bud() {
    let (mut a, mut b) = pair();
    let mut c = join(&mut a);
    let trashed = trash_on_both(&mut a, &mut b, "Launch the newsletter.md");
    send(&a, &mut c);
    let old_id = b.vault.doc_id(&trashed).unwrap().unwrap();

    b.vault.restore(&trashed).unwrap();
    b.vault.sync().unwrap();
    exchange(&mut b, &mut c);
    assert!(c.exists("Launch the newsletter.md"));
    a.vault.delete_forever(&trashed).unwrap();
    a.vault.sync().unwrap();
    // The deletion reaches each before they hear from each other: each keeps its own copy.
    send(&a, &mut b);
    send(&a, &mut c);
    for _ in 0..2 {
        exchange(&mut b, &mut c);
        exchange(&mut a, &mut b);
        exchange(&mut a, &mut c);
    }

    let kept = b.vault.doc_id("Launch the newsletter.md").unwrap().unwrap();
    assert_ne!(kept, old_id);
    for replica in [&a, &c] {
        assert_eq!(
            replica.vault.doc_id("Launch the newsletter.md").unwrap(),
            Some(kept.clone())
        );
    }
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
    assert_eq!(fingerprint(b.dir.path()), fingerprint(c.dir.path()));

    // The copies keep syncing: an edit on one reaches the others once.
    let child = "Launch the newsletter/Pick a name.md";
    let text = c.read(child);
    c.write(child, &format!("{text}\nShort and plain.\n"));
    c.rescan_and_sync();
    exchange(&mut b, &mut c);
    exchange(&mut a, &mut b);
    for replica in [&a, &b] {
        assert_eq!(replica.read(child), c.read(child));
        assert_eq!(replica.read(child).matches("Short and plain.").count(), 1);
    }
}

#[test]
fn a_deletion_that_could_not_remove_the_file_is_tried_again_on_the_next_sync() {
    use std::os::unix::fs::PermissionsExt;
    let (mut a, mut b) = pair();
    let trashed = trash_on_both(&mut a, &mut b, "Gift ideas.md");
    a.vault.delete_forever(&trashed).unwrap();
    a.vault.sync().unwrap();

    let trash = b.dir.path().join(".trash");
    let probe = trash.join("probe");
    std::fs::write(&probe, "").unwrap();
    std::fs::set_permissions(&trash, std::fs::Permissions::from_mode(0o555)).unwrap();
    if std::fs::remove_file(&probe).is_ok() {
        // Root removes files from a read-only folder: nothing here can make the removal fail.
        std::fs::set_permissions(&trash, std::fs::Permissions::from_mode(0o755)).unwrap();
        eprintln!("skipped: a read-only folder does not stop this user");
        return;
    }
    send(&a, &mut b);
    std::fs::set_permissions(&trash, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::remove_file(&probe).unwrap();
    assert!(b.exists(&trashed), "the file could not go");

    b.vault.sync().unwrap();
    assert!(!b.exists(&trashed));
    assert!(b.vault.bud(&trashed).unwrap().is_none());
    assert_eq!(b.vault.doc_id(&trashed).unwrap(), None);
    exchange(&mut a, &mut b);
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn the_same_outside_edit_on_two_devices_is_kept_once() {
    let (mut a, mut b) = pair();
    let text = a.read("Gift ideas.md");
    let edited = format!("{text}Written elsewhere\n");
    a.write("Gift ideas.md", &edited);
    b.write("Gift ideas.md", &edited);
    a.rescan_and_sync();
    b.rescan_and_sync();
    exchange(&mut a, &mut b);
    for replica in [&a, &b] {
        assert_eq!(replica.read("Gift ideas.md"), edited);
        assert_eq!(replica.vault.pending_changes().unwrap(), 0);
    }
    // Edits after it still merge as edits.
    a.write("Gift ideas.md", &format!("{edited}From a\n"));
    b.write(
        "Gift ideas.md",
        &edited.replace("Written elsewhere", "From b\nWritten elsewhere"),
    );
    a.rescan_and_sync();
    b.rescan_and_sync();
    exchange(&mut a, &mut b);
    assert_eq!(a.read("Gift ideas.md"), b.read("Gift ideas.md"));
    let merged = a.read("Gift ideas.md");
    assert_eq!(merged.matches("From a").count(), 1);
    assert_eq!(merged.matches("From b").count(), 1);
    assert_eq!(merged.matches("Written elsewhere").count(), 1);
}

#[test]
fn the_same_file_written_beside_a_folder_bud_on_two_devices_is_kept_once() {
    let (mut a, mut b) = pair();
    let text = "---\npinned: true\n---\nWritten elsewhere\n";
    a.write("Routines.md", text);
    b.write("Routines.md", text);
    a.rescan_and_sync();
    b.rescan_and_sync();
    exchange(&mut a, &mut b);
    for replica in [&a, &b] {
        assert_eq!(replica.read("Routines.md"), text);
        assert_eq!(replica.vault.pending_changes().unwrap(), 0);
    }
    assert_eq!(
        a.vault.doc_id("Routines.md").unwrap(),
        b.vault.doc_id("Routines.md").unwrap()
    );
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn a_folder_bud_trashed_on_purpose_stays_when_its_last_child_goes() {
    let (mut a, mut b) = pair();
    let trashed = trash_on_both(&mut a, &mut b, "Routines");
    let child = format!("{trashed}/Weekly review.md");
    a.vault.delete_forever(&child).unwrap();
    a.vault.sync().unwrap();
    exchange(&mut a, &mut b);

    for replica in [&mut a, &mut b] {
        assert!(!replica.exists(&child));
        assert!(
            replica.vault.bud(&trashed).unwrap().is_some(),
            "the folder bud is still in the trash"
        );
        replica.vault.restore(&trashed).unwrap();
        assert!(replica.vault.bud("Routines").unwrap().is_some());
    }
}

#[test]
fn the_source_list_reaches_the_peer_and_a_removal_follows() {
    let (mut a, mut b) = pair();
    a.vault
        .set_source("acct-1", Some(r#"{"kind":"mail","name":"Work mail"}"#))
        .unwrap();
    a.vault
        .set_source("acct-2", Some(r#"{"kind":"calendar","name":"Home"}"#))
        .unwrap();
    exchange(&mut a, &mut b);
    let ids: Vec<String> = b
        .vault
        .sources()
        .unwrap()
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    assert_eq!(ids, ["acct-1", "acct-2"]);
    assert_eq!(
        b.vault.sources().unwrap()[0].1,
        r#"{"kind":"mail","name":"Work mail"}"#
    );

    b.vault.set_source("acct-1", None).unwrap();
    exchange(&mut a, &mut b);
    let left: Vec<String> = a
        .vault
        .sources()
        .unwrap()
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    assert_eq!(left, ["acct-2"]);
}

#[test]
fn the_panel_layout_reaches_the_peer_and_a_change_there_comes_back() {
    let (mut a, mut b) = pair();
    assert!(a.vault.layout().unwrap().is_empty());
    a.vault
        .set_layout("panels", Some(r#"{"left":["inside"],"right":["files"]}"#))
        .unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(
        b.vault.layout().unwrap(),
        [(
            "panels".to_string(),
            r#"{"left":["inside"],"right":["files"]}"#.to_string()
        )]
    );

    b.vault
        .set_layout("panels", Some(r#"{"left":["files"],"right":["inside"]}"#))
        .unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(
        a.vault.layout().unwrap()[0].1,
        r#"{"left":["files"],"right":["inside"]}"#
    );

    a.vault.set_layout("panels", None).unwrap();
    exchange(&mut a, &mut b);
    assert!(b.vault.layout().unwrap().is_empty());
}

#[test]
fn a_boards_columns_reach_the_peer_and_a_change_there_comes_back() {
    let (mut a, mut b) = pair();
    assert!(a.vault.board().unwrap().is_empty());
    a.vault
        .set_board("bud-1", Some(r#"{"tags":["researching","waiting"]}"#))
        .unwrap();
    a.vault
        .set_board("bud-2", Some(r#"{"tags":["doing"]}"#))
        .unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(
        b.vault.board().unwrap(),
        [
            (
                "bud-1".to_string(),
                r#"{"tags":["researching","waiting"]}"#.to_string()
            ),
            ("bud-2".to_string(), r#"{"tags":["doing"]}"#.to_string()),
        ]
    );

    b.vault
        .set_board("bud-1", Some(r#"{"tags":["waiting"]}"#))
        .unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(a.vault.board().unwrap()[0].1, r#"{"tags":["waiting"]}"#);

    a.vault.set_board("bud-2", None).unwrap();
    exchange(&mut a, &mut b);
    assert_eq!(b.vault.board().unwrap().len(), 1);
}

#[test]
fn a_folder_file_deleted_outside_leaves_the_bud_at_its_folder_with_its_identity() {
    let (mut a, mut b) = pair();
    a.write("Routines.md", "---\npinned: true\n---\nWritten elsewhere\n");
    a.rescan_and_sync();
    exchange(&mut a, &mut b);
    let id = a
        .vault
        .doc_id("Routines.md")
        .unwrap()
        .expect("the folder file has a document");
    let child = "Routines/Weekly review.md";
    let child_id = a.vault.doc_id(child).unwrap();

    std::fs::remove_file(a.dir.path().join("Routines.md")).unwrap();
    a.rescan_and_sync();
    assert!(
        !a.dir.path().join("Routines.md").exists(),
        "a deletion stands"
    );
    assert_eq!(a.vault.doc_id("Routines").unwrap(), Some(id.clone()));
    assert_eq!(a.vault.doc_id(child).unwrap(), child_id);
    assert_eq!(
        a.vault.bud(child).unwrap().unwrap().parent.as_deref(),
        Some("Routines")
    );
    exchange(&mut a, &mut b);
    assert!(
        !b.dir.path().join("Routines.md").exists(),
        "the other replica's file goes too, not left empty"
    );
    assert_eq!(b.vault.doc_id("Routines").unwrap(), Some(id));
    assert_eq!(b.vault.doc_id(child).unwrap(), child_id);
    assert_eq!(
        b.vault.bud(child).unwrap().unwrap().parent.as_deref(),
        Some("Routines")
    );
    exchange(&mut a, &mut b);
    assert!(!a.dir.path().join("Routines.md").exists());
    assert!(!b.dir.path().join("Routines.md").exists());
}

//! Two vaults edited apart converge after a reconnect. Each test cuts the transport between
//! steps: a step edits one replica or the other, `converge` is the reconnect, and both folders
//! must then be byte for byte the same.

mod common;

use bud_core::State;
use common::{fingerprint, pair, Replica};
use pretty_assertions::assert_eq;

/// Every document one replica holds, merged into the other. Files written.
fn send_all(from: &Replica, to: &mut Replica) -> usize {
    let mut written = 0;
    for bud in from.vault.all().unwrap() {
        let Some(id) = from.vault.doc_id(&bud.path).unwrap() else {
            continue;
        };
        let bytes = from.vault.doc_bytes(&bud.path).unwrap().unwrap();
        written += to.vault.merge_doc(&id, &bytes).unwrap().written;
    }
    written
}

/// The reconnect: every document and the tree travel both ways until nothing is written.
fn converge(a: &mut Replica, b: &mut Replica) {
    a.vault.sync().unwrap();
    b.vault.sync().unwrap();
    for _ in 0..3 {
        let (a_tree, b_tree) = (a.vault.tree_bytes().unwrap(), b.vault.tree_bytes().unwrap());
        a.vault.merge_tree(&b_tree).unwrap();
        b.vault.merge_tree(&a_tree).unwrap();
        let written = send_all(a, b) + send_all(b, a);
        a.vault.sync().unwrap();
        b.vault.sync().unwrap();
        if written == 0 {
            break;
        }
    }
    assert_eq!(fingerprint(a.dir.path()), fingerprint(b.dir.path()));
}

#[test]
fn the_same_body_edited_on_both_keeps_both_edits() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Design notes.md";
    a.write(path, "## Voice\n\nWarm, not corporate.\nShort sentences.\n");
    b.write(path, "## Tone and voice\n\nWarm, not corporate.\n");
    converge(&mut a, &mut b);
    let merged = "## Tone and voice\n\nWarm, not corporate.\nShort sentences.\n";
    assert_eq!(a.read(path), merged);
    assert_eq!(b.read(path), merged);
}

#[test]
fn a_bud_trashed_on_one_and_edited_on_the_other_keeps_the_edit_in_the_trash() {
    let (mut a, mut b) = pair();
    let path = "Gift ideas.md";
    a.vault.trash(path).unwrap();
    let original = b.read(path);
    b.write(path, &format!("{original}A scarf.\n"));
    converge(&mut a, &mut b);
    for replica in [&a, &b] {
        assert!(!replica.exists(path));
        assert!(replica.read(".trash/Gift ideas.md").ends_with("A scarf.\n"));
    }
}

#[test]
fn the_same_bud_renamed_differently_on_both_ends_with_one_name() {
    let (mut a, mut b) = pair();
    a.vault.rename("Gift ideas.md", "Present ideas").unwrap();
    b.vault.rename("Gift ideas.md", "Things to give").unwrap();
    converge(&mut a, &mut b);
    let (one, other) = ("Present ideas.md", "Things to give.md");
    assert!(!a.exists("Gift ideas.md"));
    assert!(a.exists(one) != a.exists(other), "one name, not two");
    assert_eq!(a.exists(one), b.exists(one));
    assert_eq!(a.exists(other), b.exists(other));
    // The winner holds: a second reconnect changes nothing.
    let before = fingerprint(a.dir.path());
    converge(&mut a, &mut b);
    assert_eq!(fingerprint(a.dir.path()), before);
}

#[test]
fn a_bud_moved_on_one_while_its_parent_is_trashed_on_the_other_keeps_the_move() {
    let (mut a, mut b) = pair();
    let child = "Launch the newsletter/Design notes.md";
    a.vault.move_to(child, Some("Routines")).unwrap();
    b.vault.trash("Launch the newsletter.md").unwrap();
    converge(&mut a, &mut b);
    for replica in [&a, &b] {
        assert!(replica.exists("Routines/Design notes.md"), "the move wins");
        assert!(!replica.exists(child));
        assert!(!replica.exists(".trash/Launch the newsletter/Design notes.md"));
        assert!(
            replica.exists(".trash/Launch the newsletter.md"),
            "the parent stays trashed"
        );
        assert!(replica.exists(".trash/Launch the newsletter/Pick a name.md"));
    }
}

#[test]
fn a_to_do_done_on_one_and_reopened_on_the_other_after_ends_open() {
    let (mut a, mut b) = pair();
    let path = "Launch the newsletter/Set up the sender.md";
    a.vault.set_state(path, State::Done).unwrap();
    converge(&mut a, &mut b);
    assert!(b.read(path).contains("state: done"));
    b.vault.set_state(path, State::Open).unwrap();
    converge(&mut a, &mut b);
    assert!(a.read(path).contains("state: open"), "the later state wins");
    assert!(b.read(path).contains("state: open"));
}

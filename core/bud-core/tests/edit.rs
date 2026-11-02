//! Editing through the vault: every operation is a file operation first, then the index row.

use bud_core::{sanitize_filename, Bud, Error, Kind, Place, State, Vault};
use pretty_assertions::assert_eq;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

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

fn read(root: &Path, name: &str) -> String {
    std::fs::read_to_string(root.join(name)).unwrap()
}

/// Every row, with the mtime left out: a folder's own mtime moves when its entries do.
fn rows(vault: &Vault) -> Vec<Bud> {
    vault
        .all()
        .unwrap()
        .into_iter()
        .map(|mut bud| {
            bud.mtime = 0;
            bud
        })
        .collect()
}

/// The index agrees with what a fresh walk of the folder would make of it.
fn assert_matches_rescan(vault: &mut Vault) {
    let before = rows(vault);
    vault.rescan().unwrap();
    assert_eq!(rows(vault), before);
}

const TREE: [(&str, &str); 4] = [
    ("Launch.md", "---\nstate: open\n---\nTop\n"),
    ("Launch/Name.md", "Name body\n"),
    ("Launch/Name/Shortlist.md", "Shortlist body\n"),
    ("Other.md", "Other body\n"),
];

#[test]
fn sanitizes_file_names() {
    assert_eq!(sanitize_filename("Plain title"), "Plain title");
    assert_eq!(
        sanitize_filename("a/b\\c:d*e?f\"g<h>i|j"),
        "a b c d e f g h i j"
    );
    assert_eq!(sanitize_filename("  padded  "), "padded");
    assert_eq!(sanitize_filename(".hidden"), "hidden");
    assert_eq!(sanitize_filename("..."), "Untitled");
    assert_eq!(sanitize_filename(". .x"), "x");
    assert_eq!(sanitize_filename(""), "Untitled");
    assert_eq!(sanitize_filename(" / "), "Untitled");
    assert_eq!(sanitize_filename("v1.2 notes"), "v1.2 notes");
}

#[test]
fn creates_at_the_root_with_created_and_an_empty_body() {
    let (mut vault, dir, _index) = vault_with(&[]);
    let path = vault.create(None, "Gift ideas", Kind::Note, None).unwrap();
    assert_eq!(path, "Gift ideas.md");
    let text = read(dir.path(), &path);
    assert!(text.starts_with("---\ncreated: "), "{text}");
    assert!(text.ends_with("---\n"), "{text}");
    assert!(!text.contains("state"));
    let bud = vault.bud(&path).unwrap().unwrap();
    assert_eq!(bud.kind, Kind::Note);
    assert_eq!(bud.parent, None);
    assert_eq!(bud.place, Place::Everything);
    assert_eq!(bud.body, "");
    let created = bud.created.unwrap();
    assert_eq!(created.len(), 20, "{created}");
    assert!(created.starts_with("20") && created.ends_with('Z'));
    assert_matches_rescan(&mut vault);
}

#[test]
fn creates_a_todo_with_state_and_source() {
    let (mut vault, dir, _index) = vault_with(&[]);
    let path = vault
        .create(None, "Call the printer", Kind::Todo, Some("phone"))
        .unwrap();
    let text = read(dir.path(), &path);
    assert!(text.contains("state: open\n"));
    assert!(text.contains("source: phone\n"));
    let bud = vault.bud(&path).unwrap().unwrap();
    assert!(bud.is_todo());
    assert_eq!(bud.state, Some(State::Open));
    assert_eq!(bud.source.as_deref(), Some("phone"));
}

#[test]
fn creates_nested_and_makes_the_parent_folder() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let path = vault
        .create(Some("Other.md"), "Child", Kind::Note, None)
        .unwrap();
    assert_eq!(path, "Other/Child.md");
    assert!(dir.path().join("Other").is_dir());
    let bud = vault.bud(&path).unwrap().unwrap();
    assert_eq!(bud.parent.as_deref(), Some("Other.md"));
    assert_eq!(vault.children("Other.md").unwrap().len(), 1);

    let deeper = vault
        .create(Some("Launch/Name.md"), "Deeper", Kind::Todo, None)
        .unwrap();
    assert_eq!(deeper, "Launch/Name/Deeper.md");
    assert_matches_rescan(&mut vault);
}

#[test]
fn creates_in_the_inbox() {
    let (mut vault, dir, _index) = vault_with(&[]);
    let path = vault
        .create(Some("Inbox"), "Quick thought", Kind::Note, Some("share"))
        .unwrap();
    assert_eq!(path, "Inbox/Quick thought.md");
    assert!(dir.path().join("Inbox").is_dir());
    let bud = vault.bud(&path).unwrap().unwrap();
    assert_eq!(bud.place, Place::Inbox);
    assert_eq!(bud.parent, None);
    assert_eq!(vault.roots(Place::Inbox).unwrap().len(), 1);
    assert_matches_rescan(&mut vault);
}

#[test]
fn a_colliding_title_gets_a_number() {
    let (mut vault, _dir, _index) = vault_with(&[("Note.md", "x")]);
    let second = vault.create(None, "Note", Kind::Note, None).unwrap();
    let third = vault.create(None, "Note", Kind::Note, None).unwrap();
    assert_eq!(second, "Note 2.md");
    assert_eq!(third, "Note 3.md");
    assert_eq!(vault.bud("Note 3.md").unwrap().unwrap().title, "Note 3");
    let inbox = vault
        .create(Some("Inbox"), "Note", Kind::Note, None)
        .unwrap();
    assert_eq!(inbox, "Inbox/Note.md");
}

#[test]
fn a_title_is_made_safe_for_a_file_name() {
    let (mut vault, dir, _index) = vault_with(&[]);
    let path = vault.create(None, "../a/b: c?", Kind::Note, None).unwrap();
    assert_eq!(path, "a b  c.md");
    assert!(dir.path().join(&path).is_file());
    assert_eq!(
        vault.create(None, "///", Kind::Note, None).unwrap(),
        "Untitled.md"
    );
}

#[test]
fn creating_under_an_unknown_parent_is_an_error() {
    let (mut vault, _dir, _index) = vault_with(&[]);
    let err = vault
        .create(Some("Missing.md"), "x", Kind::Note, None)
        .unwrap_err();
    assert!(matches!(err, Error::NoSuchBud(_)));
}

#[test]
fn set_body_replaces_the_body_and_keeps_the_frontmatter() {
    let source = "---\n# by hand\ntags: [a]\nstate: open\n---\nOld body\n";
    let (mut vault, dir, _index) = vault_with(&[("Note.md", source)]);
    vault.set_body("Note.md", "New body\n\nSecond\n").unwrap();
    assert_eq!(
        read(dir.path(), "Note.md"),
        "---\n# by hand\ntags: [a]\nstate: open\n---\nNew body\n\nSecond\n"
    );
    assert_eq!(
        vault.bud("Note.md").unwrap().unwrap().body,
        "New body\n\nSecond\n"
    );
    assert!(!dir.path().join("Note.md.tmp").exists());

    vault.set_body("Note.md", "").unwrap();
    assert_eq!(vault.bud("Note.md").unwrap().unwrap().body, "");
    assert_matches_rescan(&mut vault);
}

#[test]
fn set_body_on_a_file_without_frontmatter_and_on_a_folder_bud() {
    let (mut vault, dir, _index) = vault_with(&[("Plain.md", "old"), ("Thread/Child.md", "c")]);
    vault.set_body("Plain.md", "new").unwrap();
    assert_eq!(read(dir.path(), "Plain.md"), "new");
    vault.set_body("Thread", "Thread notes\n").unwrap();
    assert_eq!(read(dir.path(), "Thread.md"), "Thread notes\n");
    assert_eq!(vault.children("Thread.md").unwrap().len(), 1);
    assert!(matches!(
        vault.set_body("Nope.md", "x").unwrap_err(),
        Error::NoSuchBud(_)
    ));
}

#[test]
fn rename_moves_the_file_and_its_folder_and_rewrites_descendants() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let new = vault.rename("Launch.md", "Ship it").unwrap();
    assert_eq!(new, "Ship it.md");
    assert!(dir.path().join("Ship it.md").is_file());
    assert!(dir.path().join("Ship it/Name/Shortlist.md").is_file());
    assert!(!dir.path().join("Launch.md").exists());
    assert!(!dir.path().join("Launch").exists());

    assert!(vault.bud("Launch.md").unwrap().is_none());
    let top = vault.bud("Ship it.md").unwrap().unwrap();
    assert_eq!(top.title, "Ship it");
    assert_eq!(top.state, Some(State::Open));
    let mid = vault.bud("Ship it/Name.md").unwrap().unwrap();
    assert_eq!(mid.parent.as_deref(), Some("Ship it.md"));
    let leaf = vault.bud("Ship it/Name/Shortlist.md").unwrap().unwrap();
    assert_eq!(leaf.parent.as_deref(), Some("Ship it/Name.md"));
    assert_eq!(vault.all().unwrap().len(), 4);
    assert_matches_rescan(&mut vault);
}

#[test]
fn rename_a_middle_bud_and_a_folder_only_bud() {
    let (mut vault, _dir, _index) = vault_with(&TREE);
    assert_eq!(
        vault.rename("Launch/Name.md", "Pick a name").unwrap(),
        "Launch/Pick a name.md"
    );
    let leaf = vault
        .bud("Launch/Pick a name/Shortlist.md")
        .unwrap()
        .unwrap();
    assert_eq!(leaf.parent.as_deref(), Some("Launch/Pick a name.md"));

    let (mut vault, _dir, _index) = vault_with(&[("Thread/Child.md", "c")]);
    assert_eq!(vault.rename("Thread", "Renamed").unwrap(), "Renamed");
    let child = vault.bud("Renamed/Child.md").unwrap().unwrap();
    assert_eq!(child.parent.as_deref(), Some("Renamed"));
    assert_eq!(vault.bud("Renamed").unwrap().unwrap().title, "Renamed");
    assert_matches_rescan(&mut vault);
}

#[test]
fn rename_onto_an_existing_name_is_an_error() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let err = vault.rename("Other.md", "Launch").unwrap_err();
    assert!(matches!(err, Error::Exists(_)));
    assert!(dir.path().join("Other.md").is_file());
    assert!(vault.bud("Other.md").unwrap().is_some());
    assert_eq!(vault.rename("Other.md", "Other").unwrap(), "Other.md");
}

#[test]
fn move_to_carries_the_folder_and_the_descendants() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let new = vault.move_to("Launch/Name.md", Some("Other.md")).unwrap();
    assert_eq!(new, "Other/Name.md");
    assert!(dir.path().join("Other/Name/Shortlist.md").is_file());
    assert!(!dir.path().join("Launch/Name.md").exists());
    let moved = vault.bud("Other/Name.md").unwrap().unwrap();
    assert_eq!(moved.parent.as_deref(), Some("Other.md"));
    let leaf = vault.bud("Other/Name/Shortlist.md").unwrap().unwrap();
    assert_eq!(leaf.parent.as_deref(), Some("Other/Name.md"));
    assert_eq!(vault.all().unwrap().len(), 4);
    assert_matches_rescan(&mut vault);
}

#[test]
fn move_to_the_root_and_into_places() {
    let (mut vault, _dir, _index) = vault_with(&TREE);
    let root = vault.move_to("Launch/Name.md", None).unwrap();
    assert_eq!(root, "Name.md");
    let bud = vault.bud("Name.md").unwrap().unwrap();
    assert_eq!(bud.parent, None);
    assert_eq!(
        vault
            .bud("Name/Shortlist.md")
            .unwrap()
            .unwrap()
            .parent
            .as_deref(),
        Some("Name.md")
    );

    let archived = vault.move_to("Name.md", Some("Archive")).unwrap();
    assert_eq!(archived, "Archive/Name.md");
    let bud = vault.bud(&archived).unwrap().unwrap();
    assert_eq!(bud.place, Place::Archive);
    assert_eq!(bud.parent, None);
    let leaf = vault.bud("Archive/Name/Shortlist.md").unwrap().unwrap();
    assert_eq!(leaf.place, Place::Archive);
    assert_matches_rescan(&mut vault);
}

#[test]
fn moving_into_itself_or_a_descendant_is_an_error() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let before = rows(&vault);
    for target in ["Launch.md", "Launch/Name.md", "Launch/Name/Shortlist.md"] {
        let err = vault.move_to("Launch.md", Some(target)).unwrap_err();
        assert!(matches!(err, Error::Invalid(_)), "{target}: {err}");
    }
    assert!(dir.path().join("Launch.md").is_file());
    assert_eq!(rows(&vault), before);
    assert_eq!(vault.move_to("Launch.md", None).unwrap(), "Launch.md");
}

#[test]
fn move_onto_an_existing_name_is_an_error() {
    let (mut vault, _dir, _index) = vault_with(&[("A/Same.md", "1"), ("Same.md", "2")]);
    let err = vault.move_to("A/Same.md", None).unwrap_err();
    assert!(matches!(err, Error::Exists(_)));
}

#[test]
fn trash_and_restore_round_trip() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    let before = rows(&vault);
    vault.trash("Launch/Name.md").unwrap();
    assert!(dir.path().join(".trash/Launch/Name.md").is_file());
    assert!(dir.path().join(".trash/Launch/Name/Shortlist.md").is_file());
    assert!(!dir.path().join("Launch/Name.md").exists());
    assert!(!dir.path().join("Launch/Name").exists());

    let trashed = vault.bud(".trash/Launch/Name.md").unwrap().unwrap();
    assert_eq!(trashed.place, Place::Trash);
    let leaf = vault
        .bud(".trash/Launch/Name/Shortlist.md")
        .unwrap()
        .unwrap();
    assert_eq!(leaf.place, Place::Trash);
    assert_eq!(leaf.parent.as_deref(), Some(".trash/Launch/Name.md"));
    assert!(vault.bud("Launch/Name.md").unwrap().is_none());
    assert_matches_rescan(&mut vault);

    let back = vault.restore(".trash/Launch/Name.md").unwrap();
    assert_eq!(back, "Launch/Name.md");
    assert!(dir.path().join("Launch/Name/Shortlist.md").is_file());
    assert!(!dir.path().join(".trash/Launch").exists());
    assert_eq!(rows(&vault), before);
    assert_matches_rescan(&mut vault);
}

#[test]
fn trash_a_top_level_bud_and_restore_it() {
    let (mut vault, dir, _index) = vault_with(&TREE);
    vault.trash("Launch.md").unwrap();
    assert!(dir.path().join(".trash/Launch.md").is_file());
    let top = vault.bud(".trash/Launch.md").unwrap().unwrap();
    assert_eq!(top.place, Place::Trash);
    assert_eq!(top.parent, None);
    assert_eq!(vault.roots(Place::Trash).unwrap().len(), 1);
    vault.restore(".trash/Launch.md").unwrap();
    assert!(dir.path().join("Launch/Name/Shortlist.md").is_file());
    assert_eq!(vault.roots(Place::Everything).unwrap().len(), 2);
    assert_matches_rescan(&mut vault);
}

#[test]
fn trash_and_restore_refuse_the_wrong_place() {
    let (mut vault, _dir, _index) = vault_with(&[("Note.md", "x"), (".trash/Old.md", "y")]);
    assert!(matches!(
        vault.restore("Note.md").unwrap_err(),
        Error::Invalid(_)
    ));
    assert!(matches!(
        vault.trash(".trash/Old.md").unwrap_err(),
        Error::Invalid(_)
    ));
}

#[test]
fn set_state_and_set_pinned_write_the_file_and_never_cascade() {
    let (mut vault, dir, _index) = vault_with(&[
        ("Parent.md", "---\nstate: open\n---\nP\n"),
        ("Parent/Kid.md", "---\nstate: open\n---\nK\n"),
    ]);
    vault.set_state("Parent.md", State::Done).unwrap();
    assert_eq!(read(dir.path(), "Parent.md"), "---\nstate: done\n---\nP\n");
    assert_eq!(
        vault.bud("Parent.md").unwrap().unwrap().state,
        Some(State::Done)
    );
    let kid = vault.bud("Parent/Kid.md").unwrap().unwrap();
    assert_eq!(kid.state, Some(State::Open));
    assert_eq!(
        read(dir.path(), "Parent/Kid.md"),
        "---\nstate: open\n---\nK\n"
    );

    vault.set_state("Parent.md", State::Open).unwrap();
    vault.set_pinned("Parent.md", true).unwrap();
    assert_eq!(
        read(dir.path(), "Parent.md"),
        "---\nstate: open\npinned: true\n---\nP\n"
    );
    assert!(vault.bud("Parent.md").unwrap().unwrap().pinned);
    vault.set_pinned("Parent.md", false).unwrap();
    assert!(!vault.bud("Parent.md").unwrap().unwrap().pinned);
    assert_eq!(read(dir.path(), "Parent.md"), "---\nstate: open\n---\nP\n");
}

fn set_mode(path: &Path, mode: u32) {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode)).unwrap();
}

const FAILING: [(&str, &str); 4] = [
    ("Locked.md", "L"),
    ("Locked/Existing.md", "E"),
    ("Mover.md", "M"),
    ("Mover/Child.md", "C"),
];

fn assert_untouched(vault: &Vault, dir: &Path, before: &[Bud]) {
    assert_eq!(rows(vault), before);
    assert!(dir.join("Mover.md").is_file());
    assert!(dir.join("Mover/Child.md").is_file());
    assert!(dir.join("Locked/Existing.md").is_file());
    assert!(!dir.join("Locked/Mover.md").exists());
    assert!(!dir.join("Locked/Renamed.md").exists());
}

/// A plain file stands where a folder has to be, so the move fails for every user, root included.
#[test]
fn a_move_that_cannot_make_its_folder_changes_no_row() {
    let (mut vault, dir, _index) = vault_with(&FAILING);
    std::fs::remove_dir_all(dir.path().join("Locked")).unwrap();
    std::fs::write(dir.path().join("Locked"), "not a folder").unwrap();
    std::fs::write(dir.path().join(".trash"), "not a folder").unwrap();
    vault.rescan().unwrap();
    let before = rows(&vault);

    let err = vault.move_to("Mover.md", Some("Locked.md")).unwrap_err();
    assert!(matches!(err, Error::Io(_)), "{err}");
    let err = vault.trash("Mover.md").unwrap_err();
    assert!(matches!(err, Error::Io(_)), "{err}");
    assert_eq!(rows(&vault), before);
    assert!(dir.path().join("Mover.md").is_file());
    assert!(dir.path().join("Mover/Child.md").is_file());
}

/// The same with a read-only target folder. Root ignores permission bits, so the probe decides
/// whether the folder really is locked for this user.
#[test]
fn a_move_or_rename_into_a_read_only_folder_changes_no_row() {
    let (mut vault, dir, _index) = vault_with(&FAILING);
    let before = rows(&vault);
    let locked = dir.path().join("Locked");
    set_mode(&locked, 0o555);
    let enforced = std::fs::write(locked.join(".probe"), "x").is_err();
    let moved = vault.move_to("Mover.md", Some("Locked.md"));
    let renamed = vault.rename("Locked/Existing.md", "Renamed");
    set_mode(&locked, 0o755);
    if !enforced {
        return;
    }
    assert!(matches!(moved.unwrap_err(), Error::Io(_)));
    assert!(matches!(renamed.unwrap_err(), Error::Io(_)));
    assert_untouched(&vault, dir.path(), &before);
}

#[test]
fn atomic_writes_leave_no_temp_file_in_view() {
    let (mut vault, dir, _index) = vault_with(&[("Note.md", "x")]);
    vault.set_body("Note.md", "y").unwrap();
    let names: Vec<String> = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(names, vec!["Note.md".to_string()]);
}

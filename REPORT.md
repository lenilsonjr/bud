BUILD round 2
Applied:
- Finding 1 (the failure test depends on privileges): I replaced the single permission-based test in `core/bud-core/tests/edit.rs`.
  - `a_move_that_cannot_make_its_folder_changes_no_row` puts a plain file where a folder must be, so `move_to` and `trash` fail with `Error::Io` for every user, root included. It asserts the rows and files are unchanged.
  - `a_move_or_rename_into_a_read_only_folder_changes_no_row` keeps the read-only check the ticket names. It first probes whether the folder is really locked for the current user. If it isn't (root), it returns without asserting, so the check cannot fail spuriously in CI.
  - I could not run either test as root here, so the CI behaviour is unverified.
- Finding 3 (temp file name): `write_atomic` in `core/bud-core/src/edit.rs` now writes `.<name>.tmp` in the same folder. A scan skips dot names, so a leftover temp file stays out of view. `atomic_writes_leave_no_temp_file_in_view` checks that a write leaves only the bud's own file in the folder.

Declined:
- Finding 2 (move-back failure is swallowed, and the rollback has no test): a failed move-back needs two filesystem operations to fail in a row. Making the folder rename fail after the file rename succeeded needs a privilege-dependent setup or fault injection, and the box and CI differ on privileges. The case is rare, the index stays as it was in either case, and the vault would only be split by the user's own disk problem. Adding injection hooks or changing the error type would be speculative hardening beyond this ticket.

Tests:
- `cargo fmt --all --check` was clean.
- `cargo clippy --all-targets -- -D warnings` was clean. It first flagged an unused `PathBuf` import, which I removed.
- `cargo test --workspace` passed (17 unit, 24 edit, 10 scan, 4 set_properties).
- `swift build` passed.
- `swift test` passed (9 tests).

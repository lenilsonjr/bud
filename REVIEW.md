REVIEW round 1
Reviewed: crew/BUD-15 against develop
What this does: Adds `core/bud-core/src/edit.rs` with `Vault::create`, `set_body`, `rename`, `move_to`, `trash`, `restore`, `set_state` and `set_pinned`, plus `sanitize_filename`. It writes files first, with atomic temp-file writes, and then rewrites index rows in one transaction. `set_properties` now uses the same atomic writer. `tests/edit.rs` adds 22 tests.

Ticket check:
- create (root, nested, inbox, collision, parent folder made): met
- set_body keeps frontmatter: met
- rename with sibling folder, three-level tree: met
- move_to, including the error for moving into a descendant: met
- trash and restore: met
- set_state and set_pinned never cascade: met
- atomic writes, and a failed rename or move leaves the index as it was: implemented, but the verifying test is not robust in CI (finding 1)
- filename sanitising: met
- beyond the ticket: `Error::Exists` and `Error::Invalid`, rows for intermediate trash folders, and cleanup of emptied trash folders on restore. These are reasonable.

Tests:
- I ran the gate from `work`.
  - `swift build` and `swift test` passed (9 tests).
  - `cargo fmt --all --check` was clean.
  - `cargo clippy --workspace --all-targets -- -D warnings` was clean.
  - `cargo test --workspace` passed (17 unit, 22 edit, 10 scan, 4 set_properties).
- CI is the problem: the `gate` check on 77072b7 failed, which makes this changes requested. I could not read its log. The other three required checks (iOS, macOS, tvOS) are not named as failing.
- The Rust steps in `gate.yml` pass here, so the failure most likely comes from a difference between this box and the CI container. The best-supported cause is finding 1.
- Coverage gap: no test covers a failure midway through a folder move, where the file moves but its sibling folder cannot. That path is the rollback at `edit.rs:338-340`.

Findings:
1. `core/bud-core/tests/edit.rs:422-434` bug (most likely the cause of the failing `gate`): the failure test makes the target folder read-only with `set_mode(..., 0o555)` and expects `Error::Io`.
   - `gate.yml` runs in the `swift:6.1-noble` container, where the user is root by default, and root ignores directory permission bits.
   - `move_to` and `rename` then succeed, so `unwrap_err()` panics at line 423 or 432. The test passes here only because this box runs as a non-root user.
   - To fix it, make the failure independent of privileges. Use a target that cannot work for any user, for example a plain file standing where the parent folder must be, so that `create_dir_all` or `rename` returns an error. Or skip the permission-based part when running as root, but that leaves the ticket's verification unrun in CI.
   - I did not run the test as root, so this is a finding I am confident of but have not reproduced.
2. `core/bud-core/src/edit.rs:337-342` question: if the folder rename fails, the file is moved back. If that move-back also fails, the error is swallowed with `let _ =` and the file and folder end up split, with no row change.
   - Is that acceptable? It is rare. A test of the rollback would also pin the behaviour down.
3. `core/bud-core/src/edit.rs:76-86` nit: the temp name is the target name plus `.tmp`, so it sits in the vault with a visible name. A crash between write and rename leaves a `X.md.tmp` file in the vault.
   - A rescan ignores it because it does not end in `.md`. A dot-prefixed temp name would be tidier.

verdict: changes requested

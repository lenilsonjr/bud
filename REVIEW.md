REVIEW round 2
Earlier findings:
1. Unauthenticated allocation, no timeout, unbounded tasks: addressed. The first frame from an unproven caller is capped at 16 MiB. The reader grows its buffer in 64 KiB chunks, so a claimed length costs nothing until the bytes arrive. `serve` runs under the 60 second timeout. The accept loop refuses callers beyond 16 sessions.
2. Whether a folder-only bud comes back as a duplicate: addressed. The new test `a_folder_bud_on_one_vault_comes_back_unchanged` syncs A to B and back and checks A is unchanged. A folder-only bud still arrives as an empty `.md` on the other side, and the report says so.
3. Dropped frontmatter keys hidden by a loosened test: partial, accepted. The limit is documented in the `peer.rs` module comment. The full-equality test is `#[ignore]`d with its reason. Whether to carry the other keys is left to the operator. I accept this as a reasonable decline.
4. Revocation, key rotation, one-shot tickets on the maker's side: declined as beyond the ticket. Accepted. It should go to the operator as a follow-up.
5. AAD without direction: addressed. A dialer or answerer byte is bound into the AAD, and the unit test checks a message does not open as the other side's.
6. Key file nit: declined. Accepted.
New:
- `materialize` in `core/bud-core/src/sync.rs` now writes an empty file, then nulls `buds.created` and sets the stored modification time, so the file holds only what the document says. I read it and found no defect.
- The test `a_stranger_with_an_oversized_or_silent_frame_is_dropped` does not send a silent stranger, as the report admits. The silent-stranger case is covered only by the `serve` timeout, which has no test. This does not block approval.
Tests: I did not run the gate. The host's checks on `1c318ffff84a64c98db0863b93dd660fe262f53d` passed (5 checks), and I was told to read the diff and report and not run the suite. I read the full round 2 diff of `core/bud-core/src` (`peer.rs`, `sync.rs`). The report says `tests/peer.rs` has 12 passing and 1 ignored, fmt and clippy were clean, and no Swift file changed since round 1.
verdict: approved

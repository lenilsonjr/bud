BUILD round 1
Ticket:
- Fixture at `core/bud-core/tests/fixtures/obsidian/`: met. It has `.obsidian/app.json` and `workspace.json`, `Daily/` with two dated notes, `Reading list.md` with `tags:` and `aliases:` frontmatter, and `Linked note.md` with `[[Other note]]` and `![[image.png]]`. It also has `image.png`, `Projects/Projects.md`, `Templates/Daily template.md` and `.trash/Old draft.md`. The content is fictional newsletter-world text with no personal data. `image.png` is a small text placeholder, not a real PNG. The scan skips it by extension, so the tests don't depend on its bytes.
- Every `.md` indexes as a note with no `state`, folders as buds, `.obsidian/` and the png skipped, `.trash/` as `trash`: met. `every_markdown_file_is_a_note_and_folders_are_buds` asserts all 11 rows. `settings_and_attachments_are_skipped_and_the_trash_is_a_place` asserts the skips and the trash place.
- Fixture bytes are identical after `open`, `rescan`, `search`, `today` and `counts`: met. `the_vault_bytes_are_identical_after_every_read` hashes every file before and after.
- `Projects/Projects.md` is a child of `Projects`: met. `a_folder_note_is_a_child_of_its_folder` says so explicitly (ADR-002 consequence 2).
- Wiki links stay as text in `body`: met. `wiki_links_and_embeds_stay_as_text_in_the_body` checks the exact body.

Changed:
- `core/bud-core/tests/obsidian.rs` (new)
- `core/bud-core/tests/fixtures/obsidian/` (new; all the files above)

No source changes were needed, since the crate already behaves this way.

Tests:
- 8 tests in `tests/obsidian.rs`: `the_fixture_looks_like_a_vault`, `every_markdown_file_is_a_note_and_folders_are_buds`, `settings_and_attachments_are_skipped_and_the_trash_is_a_place`, `a_folder_note_is_a_child_of_its_folder`, `wiki_links_and_embeds_stay_as_text_in_the_body`, `frontmatter_with_tags_and_aliases_is_a_note_and_its_body_is_intact`, `a_second_scan_changes_nothing` and `the_vault_bytes_are_identical_after_every_read`.
- The frontmatter test expects the body to start with a newline, because `Reading list.md` has a blank line after the closing fence. That is the existing split behaviour, so I matched it and did not change the crate.
- `swift build`: passed.
- `swift test`: passed, 13 tests.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including the 8 new tests. The one ignored test is the existing 5000-bud timing test.

Verify:
- Run `cargo test --workspace --test obsidian` from the repo root.
- To check the fixture by hand, run `find core/bud-core/tests/fixtures/obsidian`.

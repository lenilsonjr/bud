BUILD round 2

Applied:
- Finding 1, redeclared `Keycap` that broke the iOS, macOS and snapshots builds: I deleted the second `Keycap` from `Sources/BudKit/Sheets.swift`. The Esc chip now uses the existing `Keycap` from `Sources/BudKit/TopBar.swift`, the one the palette and the bar already use.
- Finding 2, how the Esc chip looks: the chip now has the same look as the palette's `esc` chip, a rounded tile filled with `Theme.line`. I could not render it here. The picture check is still open once CI is green.

Declined:
- Finding 3, scrim kept while the card is re-created: this is intended. The scrim stays steady and only the card swaps when one modal replaces another, so the dim does not flash. I changed nothing.
- Finding 4, doubt that the overlay is drawn in the first frame: the snapshot tests set `store.modal` before rendering, so `ImageRenderer` draws the overlay in its first frame and the appear transition does not apply. I left the tests as they are. The size floor stays as a weak guard, and a person looks at the pictures.
- Finding 5, missing pictures: they are produced by the macOS snapshots job. The redeclaration was the only reason it failed, and it is fixed. I can't produce the pictures here.

Tests:
- `swift build` passed.
- `swift test` passed with 0 failures, including the 6 `ModalTests`.
- `cargo fmt --all --check` was clean.
- `cargo clippy --all-targets -- -D warnings` was clean.
- `cargo test --workspace` passed.
- The SwiftUI files are still not compiled on Linux. The iOS, macOS and snapshots CI checks on the pull request are the real test of this fix.

BUILD round 2
Applied:
- Finding 1 (macOS lost the sidebar): `Sources/BudKit/Files/FilesView.swift` now decides through `sidebarShown(in:)`. It always returns true on macOS and follows `SidebarVisibility` only under `#if os(iOS)`. The Mac layout is unchanged, and the toggle exists only where the collapse does.
- Finding 3 (no VoiceOver name): the toggle in `Sources/BudKit/TopBar.swift` now has `.accessibilityLabel("Show or hide the sidebar")`.
- Finding 4 (re-render on every resize frame): `surfaceSize` in `Sources/BudKit/BudStore.swift` is no longer `@Published`. Nothing draws from it. It is only read when the button is pressed. `sidebar` stays published, so the toggle still redraws.

Declined:
- Finding 2 (compact size class ignores the choice): intended. The phone layout has its own navigator fold, so the sidebar choice does not apply there. The stored choice is harmless and is cleared on the next orientation change. Resetting it on a size-class change would be extra state with no visible benefit.
- Finding 5 and the criterion 4 verification: I cannot take screenshots at 320, 600 or 1024 pt, so this is deferred to the operator and still open. Narrow regular-width windows (600 to 700 pt, or portrait) now collapse the sidebar so the page gets the full width. Windows under the compact breakpoint use the existing phone layout. I made no further layout changes.
- Keyboard shortcuts via `.onKeyPress` instead of `.keyboardShortcut`: ⌘K already uses `.keyboardShortcut`. N, Space and Esc are bare keys that act on the canvas's focused card, so they stay as `.onKeyPress` on `OrbitCanvas` to read the lit card. A `.keyboardShortcut` on a hidden button would fire while typing in text fields. Both forms respond to a hardware keyboard, and the ticket only needs them to work.
- Tests for the SwiftUI wiring: the box cannot compile or run SwiftUI. The rule that drives it is covered by `SidebarVisibilityTests`, and the Apple builds run in CI on the pull request.

Tests:
- `swift build`: pass.
- `swift test`: pass, 105 tests, 0 failures. This includes the 5 `SidebarVisibilityTests`, which are unchanged this round because the rule did not change.
- `cargo fmt --all --check`: pass.
- `cargo clippy --all-targets -- -D warnings`: pass.
- `cargo test --workspace`: pass.
- I did not run the iOS and macOS app builds. That is for the CI on the pull request.

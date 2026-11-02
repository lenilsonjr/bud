REVIEW round 2
Earlier findings:
1. macOS lost the sidebar: addressed. `sidebarShown(in:)` in `Sources/BudKit/Files/FilesView.swift` always returns true on macOS. It follows `SidebarVisibility` only under `#if os(iOS)`, which is also the only place the toggle exists.
2. Compact size class ignores the stored choice: declined with a reasonable reason (the phone layout has its own fold, and the choice clears on the next orientation change). Accepted.
3. VoiceOver name: addressed. `.accessibilityLabel` is added in `Sources/BudKit/TopBar.swift`.
4. Re-render on every resize frame: addressed. `surfaceSize` is no longer `@Published`, and it is read only when the button is pressed.
5. Screenshots at 320, 600 and 1024 pt: unaddressed, but declined openly as deferred to the operator. The builder says they cannot take screenshots, so this stays as an open manual check for the operator on the pull request. It does not block.
New: nothing introduced by the fixes. The diff since the last review is the three small edits above.
Tests: I did not run the suite myself. The host's checks on `2ee3612e5c55bd952b20d6eec7080786c922af4c` passed (5 checks, including the iOS, macOS and tvOS builds and `gate`). I read the diff and the report. The report says `swift build`, `swift test` (105 tests), `cargo fmt`, clippy and `cargo test --workspace` pass. The rule's tests are unchanged because the rule did not change.
verdict: approved

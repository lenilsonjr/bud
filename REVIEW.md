REVIEW round 1
Reviewed: crew/BUD-33 against develop
What this does: Files now shows its sidebar only when a pure rule says so (`SidebarVisibility`). The rule is: the window is landscape and at least 700 pt wide. An iOS-only bar button overrides the rule until the window turns the other way. FilesView reports its size to the store so the button knows what it flips. Five Linux tests cover the rule.

Ticket check:
- Sidebar collapses in portrait, shows in landscape, and a bar button toggles it: partial. The logic is tested. The wiring is SwiftUI that the box cannot compile. The change also reaches macOS (finding 1).
- ⌘K, N, Space, Esc with a hardware keyboard: met by existing code. ⌘K uses `.keyboardShortcut` at `Sources/BudKit/BudRootView.swift:41`. N, Space and Esc use `.onKeyPress` at `Sources/BudKit/OrbitCanvas.swift:85-94`. I checked this by reading only. The ticket says `.keyboardShortcut` for all four, and the report does not mention the difference.
- Trackpad hover moves the light, and touch falls back to the last tap: met by existing code (`onContinuousHover` at `Sources/BudKit/OrbitCanvas.swift:64`). Not run.
- Layout at 320, 600 and 1024 pt without clipping: missing. The builder took no screenshots and made no layout change. The ticket asks for screenshots at those widths as verification.

Tests:
- `swift build` and `swift test` pass: 105 tests, 0 failures, including the 5 new `SidebarVisibilityTests`.
- `cargo fmt --all --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test --workspace` pass.
- CI: the host's checks on `d477801170074c841f71344a556782863b7ac1e0` passed (5 checks), so I ran no Apple builds. They prove only that the SwiftUI code compiles, not that it behaves correctly.
- Gap: nothing tests the SwiftUI wiring (`FilesView`, `TopBar`, the store's `surfaceSize`). The rule's tests do not cover macOS, which uses the same view.

Findings:
1. `Sources/BudKit/Files/FilesView.swift:17-27` bug: the sidebar condition is not limited to iOS. On macOS, `store.sidebar.isShown(in:)` returns false for any Files window narrower than 700 pt or taller than it is wide. The toggle exists only under `#if os(iOS)` (`Sources/BudKit/TopBar.swift:15`), so a Mac user who narrows or reshapes the window loses the sidebar with no way to bring it back. The Mac layout is the thing this ticket says to keep. Either make the automatic rule always true on macOS, or add a macOS toggle, or gate the whole change with `#if os(iOS)`.
2. `Sources/BudKit/TopBar.swift:15` design: the toggle appears only when `!compact`. If a regular-width window is narrower than 700 pt, or is portrait, the sidebar is collapsed and the button is the only way back. That works. If the size class turns compact while the user's choice is "shown", the phone layout ignores the choice, and nothing resets it. Please confirm this is intended. Question, not a certain defect.
3. `Sources/BudKit/TopBar.swift:73-86` nit: the icon-only button has no accessibility label, only `.help`. Add `.accessibilityLabel` so VoiceOver can name it.
4. `Sources/BudKit/BudStore.swift:57` design: `surfaceSize` is `@Published` and written on every resize. Every view observing the store re-renders on each frame of a Stage Manager drag. A `let`-less plain property, or local `@State` in `FilesView` with the toggle passed through, would avoid that. Finding, not a certain bug.
5. Ticket, criterion 4: no 320, 600 or 1024 pt evidence. Provide it, or say plainly that it is deferred to the operator. The report currently calls it "partial". Finding 1 must be fixed first, because it changes the layout at those widths on the Mac.

verdict: changes requested

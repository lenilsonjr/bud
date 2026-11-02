BUILD round 2

Applied:
- **Finding 1 (squeeze lands elsewhere):** in `Sources/BudKit/TopBar.swift`, the "Go anywhere" field on iOS is now `minWidth: 110, maxWidth: 180` instead of a fixed 180. It gives up to 70 pt before the pill label or the breadcrumb is squeezed. The Mac keeps the fixed 180, so its bar is unchanged. The pill keeps `layoutPriority(2)` on iOS only.
- **Finding 3 (deprecated `onChange`):** both `onChange(of:)` calls in `Sources/BudKit/Files/TreeRow.swift` now use the two-parameter form. The deployment target is iOS 17 and macOS 14, so it is available.

Declined:
- **Finding 1, padding compression:** I did not narrow the pill's own padding. The room taken from the field is the smaller change, and I can't see the bar here to show narrower padding is needed. If the pill still truncates on the device, narrowing the padding is the next step.
- **Finding 1, measured 834 pt budget or screenshot, still open:** I can't produce either without running the app, so this stays an open question for the operator. Please check the iPad Pro 11-inch portrait picture (834 pt) in CI or the simulator. The label should read "Verify the address", and the segmented control, breadcrumb and gear should not be squeezed.
- **Finding 3, first-frame unfaded label:** a long label shows unfaded for one pass before it fades. The reverse (fade until measured) would flash a fade on every label that fits, which is the ticket's bug, so I left it. The unmeasured case is tested to draw the label whole.
- **Finding 4:** the reviewer does not count it against the rule. The literals are the same mask-alpha values the old code used.

Finding 2 (answer, no change): the cut is not the 28-character `shortTitle` rule, since "Verify the address" is 18 characters. It comes from the pill's `Button` text, which has `lineLimit(1)`, being offered less than its ideal width. That is consistent with the squeeze happening in layout, but I could not confirm it on a device here.

Tests:
- `swift build`: passed.
- `swift test`: passed, 110 tests with 0 failures, including the 5 `TitleFadeTests`.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: passed.
- I added no new test, since both changes are SwiftUI layout that only compiles on the macOS runners. The pure fade rule stays covered by `TitleFadeTests`.

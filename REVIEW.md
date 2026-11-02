REVIEW round 2
Earlier findings:
1. Pill squeeze, `Sources/BudKit/TopBar.swift`: partial, and I accept it. The iOS "Go anywhere" field is now `minWidth: 110, maxWidth: 180`, so it gives up to 70 pt before the pill label or the breadcrumb is squeezed. The Mac keeps the fixed 180. The padding compression and the 834 pt screenshot are declined, and the reason is reasonable: neither can be produced without running the app. The ticket's own verification asks for iPad simulator screenshots after the merge. The operator should check the 834 pt portrait picture for "Verify the address" in full, with the segmented control, breadcrumb and gear intact. If it still truncates, narrow the pill's padding.
2. Source of the cut: addressed. The builder's answer is that the pill's `Button` text, with `lineLimit(1)`, is offered less than its ideal width, and that matches the change. It is not the 28-character rule.
3. `onChange` form and first frame, `Sources/BudKit/Files/TreeRow.swift`: addressed. Both calls now use the two-parameter form. The one-pass unfaded first frame is declined with a sound reason, since the alternative would bring back the ticket's bug.
4. Literal `.black` and `.clear` in the mask: not counted against the rule, as before.

New: nothing a fix introduced. The flexible frame clamps to 180 when there is room, so the iPad landscape bar is unchanged. The iPhone compact bar never draws the field.

Tests: I ran the box gate on the new head. `swift build` passed. `swift test` passed (110 tests, 0 failures, including the 5 `TitleFadeTests`). `cargo fmt --all --check` was clean. `cargo clippy --all-targets -- -D warnings` was clean. `cargo test --workspace` passed. The host's checks on the head, 5 in all, passed. No new test was added, which is fair for SwiftUI layout.

```
verdict: approved
```

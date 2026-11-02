REVIEW round 1
Reviewed: crew/BUD-71 against develop
What this does: On iOS the focus pill gets `layoutPriority(2)`, so it is sized before the breadcrumb, which has priority 1 (`Sources/BudKit/TopBar.swift:186`). In the Files sidebar, a title beside a count is now wrapped in `FadingTitle`, which measures the label and the room it has. The tail fade applies only when the label is wider than that room (`TitleFade.needsFade`, new, with 5 Linux tests).

Ticket check:
- Full pill label in iPad portrait at 834 pt: partial. The fix is a single priority change that nobody has seen work. The builder's report also says "partial". This is a MUST and it is not evidenced.
- Fade only when the label overlaps the count: met in code. `FadingTitle` measures the natural text width and the frame width. The count is a sibling after `Spacer(minLength: 4)`, so the frame width is the room before the count. A label that fits gets a solid mask. Not seen on a device.
- Mac and iPhone unchanged: pill met, because it sits inside `#if os(iOS)` and the iPhone bar uses the compact layout. Sidebar: partial. The Mac sidebar changes for a long label that fits, which is the point of the ticket. The snapshot pictures were not run by the builder, and no snapshot is visible in the diff.
- Beyond the ticket: none. `REPORT.md` appears in the diff at the repo root, which is the crew's own report file.

Tests:
- `TitleFadeTests` covers the pure rule: fits, exactly full, overlaps, unmeasured, and noise under 0.5 pt. That is good coverage of the rule.
- Nothing covers the two layout changes, and the pill change has no test or evidence at all.
- I ran the whole box gate from `work`: `swift build` passed. `swift test` passed (110 tests, 0 failures; the only warning is an unused `done` in `CloseBranchTests`, which predates this branch). `cargo fmt --all --check` was clean. `cargo clippy --all-targets -- -D warnings` was clean. `cargo test --workspace` passed.
- The host's checks on the head, 5 in all, passed. They compile the SwiftUI files but do not check layout.

Findings:
1. Sources/BudKit/TopBar.swift:186 design: `layoutPriority(2)` on the pill only changes who gets space first. Space the other items need is then taken from them, and the `.frame(width: 180)` on `goAnywhere` (line 211) cannot shrink. At 834 pt, with the segmented control, breadcrumb, 180 pt search field, Add here, an optional zoom control, the gear and the ELSEWHERE tag, the squeeze could land on the segmented control, the breadcrumb or the gear instead, or push the bar past its edge. The result is unseen in either orientation. The ticket asks for the label to be kept, with the pill allowed to "compress its padding before it truncates", and the builder names that as the next step. Please do the compression now: for example narrower paddings on iOS, and let `goAnywhere` give way before the pill label does. Then give a measured 834 pt width budget, or a screenshot, that shows the bar still fits. If it is not possible to show this here, say so as an open question for the operator.
2. Sources/BudKit/TopBar.swift:171-176 question: is truncation at 834 pt coming from the pill's own `Button` text (`lineLimit(1)`) being offered less than its ideal width? If so, the priority change fixes it. If the cut also comes from the 28-character `shortTitle` rule, "Verify the address" (18 characters) is unaffected. Please confirm which one it is, since the fix depends on it.
3. Sources/BudKit/Files/TreeRow.swift:79-86 nit: both measurements start at 0, so the first frame draws a solid mask and a long label shows unfaded for one pass before it fades. `onChange(of:)` with a single parameter is deprecated on newer SDKs; the builder flagged this too. Use the two-parameter form if the deployment target allows it.
4. Sources/BudKit/Files/TreeRow.swift:93 nit: `.black` and `.clear` are literal colours in a view. They are used only as mask alpha, as the code it replaced did, so I do not count them against the hard rule.

The pill change is a MUST criterion with no evidence, and I can see a plausible way it shifts the truncation to another control, so another round is needed.

```
verdict: changes requested
```

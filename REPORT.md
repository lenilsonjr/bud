BUILD round 1
Ticket:
- **Full focus pill label in iPad portrait at 834 pt:** partial. On iOS the pill now has `layoutPriority(2)`, so it is sized before the breadcrumb, which has priority 1. Its padding was not changed. I could not run the iPad here, so the 834 pt picture has not been seen.
- **Tail fade only when the label overlaps the count:** met in code, but I could not run it. `TitleFade.needsFade` decides it, and `FadingTitle` in `TreeRow` measures the label and its room. A label that fits gets a solid mask, so it is drawn whole. The sidebar views compile only on the macOS runners.
- **Mac and iPhone pictures unchanged:** met as far as I can tell. The pill change is inside `#if os(iOS)`. The iPhone bar uses the compact layout and never draws the pill. The Mac sidebar picture changes only for a long label that fits. I did not run the snapshot pictures.

Changed: `Sources/BudKit/TitleFade.swift` (new), `Sources/BudKit/Files/TreeRow.swift`, `Sources/BudKit/TopBar.swift`, `Tests/BudKitTests/TitleFadeTests.swift` (new)

Tests: I added `TitleFadeTests` with 5 cases: a label that fits, one that fills the room exactly, one that overlaps, nothing measured yet, and rounding noise under 0.5 pt. All pass. Gate:
- `swift build`: passed.
- `swift test`: passed, 110 tests with 0 failures.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: passed.

Verify:
- **Focus pill:** on an iPad Pro 11-inch in portrait at 834 pt, the top bar pill should read "Verify the address" in full. In landscape and in a 1024 pt window it should be unchanged.
- **Sidebar row:** in the Files sidebar, "Launch the newsletter" should show its last letter unfaded. A label that really runs under the count should still fade. If the pill still truncates, the next step is to compress its padding before the label gives way.
- **Mac and iPhone:** the snapshot pictures should be unchanged. I'd also confirm the `build (iOS)` and `build (macOS)` checks on the pull request are green. `FadingTitle` uses the single-parameter `onChange`, which newer SDKs may warn about.

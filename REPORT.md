BUILD round 1
Ticket:
- Canvas edge to edge on tvOS: met in code, not compiled here. `.ignoresSafeArea()` is on `TVCanvas` in `BudTVView.body`, so the background, the lines and the cards fill the screen. The window background has it too. The trail overlay is added after it, so the trail stays inside the safe area.
- Soft glow instead of the system focus lift: met in code, not compiled here.
  - Each card button has `.focusEffectDisabled()`, so the system highlight is off.
  - The focused card draws a shadow in `Theme.amethyst` at 55% opacity, radius 28.
  - It also draws a 2 pt stroke of the same colour at 60%.
  - The scale lift is now 1.06 (it was 1.08).
  - `Theme.amethyst` is already adaptive: `#5B2A9E` in light mode and the lavender `#C3B2EE` in dark mode. No new theme colour was needed.
  - The old green glow and the 1.5 pt lit stroke are gone from the TV cards, so there is no white in the focus treatment.
- Hint capsule removed: met. `hint` is gone from `BudRootView` and `BudTVView` along with its strings. `grep -rn "Drag or scroll" Sources` finds nothing; I reworded one doc comment in `OrbitCanvas.swift` that matched it. The toast overlay in `BudRootView` is kept at the bottom edge with 12 pt padding. The toast code is excluded on tvOS.
- Existing tests: met. `swift test` passed 21 tests.

I wrote no new tests. The change is SwiftUI-only and the SwiftUI files don't compile on Linux, so there is nothing a Linux test can reach. The tvOS and macOS compiles are left to CI on the draft pull request.

Changed: `Sources/BudKit/TV/BudTVView.swift`, `Sources/BudKit/BudRootView.swift`, `Sources/BudKit/Toast.swift` (comment only), `Sources/BudKit/OrbitCanvas.swift` (comment only)

Tests: `swift build`, `swift test`, `cargo fmt --all --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test --workspace` all passed. No test was weakened.

Verify: On the tvOS build, move the focus across cards. The focused card should show an amethyst glow and a thin amethyst ring, with no white lift. The glow should be lavender in dark mode. The canvas background and lines should run to the screen edges while the trail stays inside the safe area. On the Mac, iPad and iPhone views there should be no capsule at the bottom, and the toast should still appear above the bottom edge.

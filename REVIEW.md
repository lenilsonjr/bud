REVIEW round 1
Reviewed: crew/BUD-49 against develop
What this does: On tvOS, `TVCanvas` now ignores the safe area and the window background does too. The trail overlay is added after `TVCanvas`, so it stays inside the safe area. Focused cards get `.focusEffectDisabled()`, an amethyst shadow at 55% opacity with radius 28, a 2 pt amethyst stroke at 60%, and a 1.06 scale. The hint capsule is removed from `BudRootView` and `BudTVView`, and the toast now sits at the bottom with 12 pt padding.

Ticket check:
- Canvas edge to edge: met. `.ignoresSafeArea()` is on `TVCanvas` (`Sources/BudKit/TV/BudTVView.swift:17`), not on the overlays. The report names the modifier.
- Focus glow: met. `.focusEffectDisabled()`, shadow, stroke and scale are all as specified. `Theme.amethyst` is already adaptive (`Palette.swift:40`: `#5B2A9E` in light mode, `#C3B2EE` in dark mode). No white is left in the focus treatment, and the old green glow is gone.
- Hint capsule removed: met. `grep` finds neither "Drag or scroll" nor the TV hint text under `Sources`. The toast stays above the bottom edge.
- Existing tests: met. CI passed.
- Beyond the ticket: none. The `OrbitCanvas.swift` and `Toast.swift` changes are comment-only.

Tests: This change touches only SwiftUI views, so there is nothing a Linux test can reach, and no new tests are reasonable. The host's checks on `f292fe8` passed (5 checks), including the tvOS, macOS and iOS builds and the gate. I did not run the suite myself, as instructed, and relied on those checks.

Findings:
1. `Sources/BudKit/TV/BudTVView.swift:51` nit: a blank line is left before the closing brace of `BudTVView` after the `hint` removal.
2. `Sources/BudKit/TV/BudTVView.swift:176` nit: the non-focused card shadow still uses `Theme.shadowStrong` and `Theme.shadow`, which is fine. The ticket does not ask for any other change there.

verdict: approved

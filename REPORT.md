BUILD round 2

Applied:
- **1 (state written while drawing, whole-layout compare each frame):**
  - `retarget` no longer runs in `frame(at:)`. It runs from `onChange(of: store.layout)`, and `MotionState` is created from `store.layout` in `OrbitCanvas.init`.
  - `frame(at:)` now only steps the simulation. The one write left is the single queued `animating = false` when the simulation reaches rest.
  - At rest, a hover or lamp redraw does no layout comparison.
- **2 (`dragging` can stick when `onEnded` never runs):**
  - A `@GestureState` grip now releases the held card and clears `dragging` whenever the gesture stops, including a cancel.
  - `onChange(of: store.layout)` also clears `dragging` if its card has left the layout.
  - `Simulation.retarget` already dropped a held id that left the layout. A new test covers that.
- **3 (first frame after a resume charged a stale `dt`):** `MotionState.retarget(to:)` and `wake()` reset the clock. The first frame after a centre change or a drag start gets `dt` 0.
- **4 (drag gesture still attached with `Motion.enabled` false):** the gesture is attached with `including: Motion.enabled ? .all : .subviews`, so with motion off the card takes no drags.
- **Test gaps the review named:** two cases added to `Tests/BudKitTests/SimulationTests.swift`:
  - A card dragged onto a neighbour nudges it while the spring runs. Both then settle with no overlap.
  - A `retarget` mid-motion with a held card removed drops that card and leaves nothing held, and the rest settle.

Declined: none.

Tests:
- `swift build`: passed.
- `swift test`: 83 tests, 0 failures. That includes the 9 `SimulationTests`.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: passed.
- The `OrbitCanvas` changes (items 1 to 4) are SwiftUI and compile only on the pull request's macOS and iOS checks, so no Linux test covers them.

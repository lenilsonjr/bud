BUILD round 1

Ticket:
- `Simulation` beside `LayoutEngine`: met. `step(dt:)` moves every card to its rest spot with an exact critically damped spring and pushes overlapping cards apart. At rest, `step` returns at once.
- Lines and light stay attached: met. The canvas draws edges, light, hit tests and the opened card from `Simulation.current`, the live positions, not the static layout.
- Settles within 1.5 s of a centre change, never visibly oscillates: met in tests. After a centre change every card is within 1 pt at 90 steps of 1/60 s. A lone displaced card's distance never grows.
- Switchable off with one constant: met. `Motion.enabled` in `Sources/BudKit/Simulation.swift`. Set to false, the canvas draws `store.layout` unchanged, with no timeline and no drag.
- Drag and let go: partial. `Simulation.hold` and `release` are tested on Linux. The drag gesture in `OrbitCanvas` is new SwiftUI code that I could not compile or run here. Its first check is the macOS and iOS build checks on the draft pull request.

Changed:
- `Sources/BudKit/Simulation.swift` (new): `Motion`, `Simulation` and a small `Vector` type, since `CGVector` is missing on Linux.
- `Sources/BudKit/OrbitCanvas.swift`:
  - A `TimelineView` steps the simulation, and pauses once every card is at rest.
  - A card drag holds the card, the others make room, and release lets it settle back.
  - The drag is a 8 pt minimum-distance gesture on each card.
  - `MotionState` is the reference-type holder for the simulation.
- `Tests/BudKitTests/SimulationTests.swift` (new).

Tests: `SimulationTests` has 7 cases:
- A card at rest costs nothing.
- A card displaced by 300 pt is back within 1 pt after 200 steps, with no overlaps.
- A lone card's distance only shrinks on the way back.
- After a centre change, every card is within 1 pt at 1.5 s.
- A new bud starts at its parent and settles.
- A held card stays put until released, then settles.
- `current` follows the live positions and keeps the same edges.

Gate, run from the repo root:
- `swift build`: passed.
- `swift test`: passed, 81 tests, 0 failures.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: passed.

I weakened no expectation.

Verify:
- Run `swift test --filter SimulationTests`.
- On the Mac build, tap a thread to change the centre and watch the cards drift and come to rest in under 1.5 s.
- Plant a bud and watch it grow out from its parent.
- Drag a card across the canvas: neighbours make room, and it springs back when released.
- Set `Motion.enabled` to false: the layout is static and the card drag is off.

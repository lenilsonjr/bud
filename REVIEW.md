REVIEW round 2
Earlier findings:
1. State written while drawing, and a whole-layout compare each frame: addressed. `retarget` now runs from `onChange(of: store.layout)`, and `MotionState` is built from `store.layout`. `frame(at:)` only steps the simulation. The one write left is the queued `animating = false` at rest, which I accept.
2. `dragging` sticking when `onEnded` never runs: addressed. A `@GestureState` grip releases the card and clears `dragging` when the gesture stops. `onChange(of: store.layout)` also clears `dragging` when its card has left the layout. `frame(at:)` no longer requires `dragging == nil` to pause, which is safe because a held card keeps the simulation from being at rest.
3. Stale `dt` on the first frame after a resume: addressed. `MotionState.retarget(to:)` and `wake()` reset the clock.
4. Drag gesture still attached with `Motion.enabled` false: addressed. The gesture is attached with `including: Motion.enabled ? .all : .subviews`.
5. Test gaps: addressed. There are two new cases: a card dragged onto a neighbour, and a retarget mid-motion that removes a held card.

New:
- Sources/BudKit/OrbitCanvas.swift:78-80 nit: the `.background(Theme.canvas.ignoresSafeArea(...))` on the canvas is not part of BUD-46 and the report does not mention it. It uses `Theme`, so it breaks no hard rule, and CI compiled it. I do not block on it. The crew should keep it only if the ticket wants it.
- I found nothing else introduced by the fixes.

Tests: I did not run the suite myself, as instructed. The host's checks on the head commit passed (5 checks), which covers the required iOS, macOS, tvOS and `gate` checks. The report says the Linux gate was clean: swift build, 83 tests, fmt, clippy and cargo test. The two new tests read correctly against `Simulation`.

verdict: approved

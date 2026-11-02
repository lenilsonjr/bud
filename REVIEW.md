REVIEW round 1
Reviewed: crew/BUD-46 against develop

What this does: Adds `Simulation` in `Sources/BudKit/Simulation.swift`. It is a pure-Swift critically damped spring toward each card's layout spot, with overlap push and a rest short-circuit. `OrbitCanvas` now draws the lines, light, hit tests and opened card from the live positions, stepped by a `TimelineView`. It also adds a per-card drag that holds a card and releases it back to its spot. `Motion.enabled` switches the motion off.

Ticket check:
- `Simulation` beside `LayoutEngine`, with a critically damped `step(dt:)`, overlap push and free rest: met. The spring step is the exact closed form and I checked the algebra. `step` returns at once when at rest.
- Lines and light attached to the moving positions: met. They are drawn from `motion.sim.current`.
- Settles within 1.5 s and never oscillates visibly: met in tests. The seed centre change is within 1 pt at 90 steps, and a lone card's distance never grows. The overlap push can still add velocity, and no test covers that case. I did not find a failing path.
- Switchable off with one constant: met. `Motion.enabled` is one constant.
- Verification tests (200 steps within 1 pt with no overlap, 300 pt displacement returns): met.
- Drag and let go: met in logic, and untested in the view. The gesture code is new SwiftUI that only CI compiled.

Tests: `SimulationTests` has 7 cases that map to the criteria. There is no test for the case where a push is active while the spring runs. There is no test for `retarget` mid-motion, which is the case where `held` is filtered or a card is removed. I did not run the suite myself because the instructions say to read the diff and the report. The host's checks on the head commit passed (5 checks), which covers the required iOS, macOS, tvOS and `gate` checks. The report says the Linux gate was clean: swift build, 81 tests, fmt, clippy and cargo test. Nobody ran the drag and the timeline in the running app. The report leaves that to the owner's screen recording.

Findings:
1. Sources/BudKit/OrbitCanvas.swift:86-92 design: `frame(at:)` changes state while the view draws. It steps the simulation, and it queues `animating = false` on the main queue. It also runs `retarget` on every frame, and that compares the whole `Layout` for equality. At rest, any redraw (hover, lamp) repeats that comparison. This is cheap for small trees but conflicts with "cards at rest cost nothing". Compare a layout revision, or compare only when `store.layout` changes through `onChange`.
2. Sources/BudKit/OrbitCanvas.swift:93 and :144 bug (unsure): `dragging` is cleared only in `onEnded`. If the dragged card leaves the layout mid-drag, or the gesture is cancelled, `onEnded` may never run. `dragging` then stays set, `frame` never pauses the timeline, and it ticks at the display rate forever. Clear `dragging` when `held` loses the card or when the id is no longer in the layout.
3. Sources/BudKit/OrbitCanvas.swift:287-294 design: `MotionState.last` keeps its old value when the timeline is resumed. The first frame after a centre change can get `dt` up to the 0.1 s clamp, so the cards jump about a quarter of the way in one frame. The nil reset only happens when a frame sees the simulation at rest. Reset `last` when `animating` flips to true.
4. Sources/BudKit/OrbitCanvas.swift:128 nit: with `Motion.enabled` false the drag gesture is still attached, so it still takes drags on a card. Only the handler body returns early, whereas the report says "the card drag is off". Attach the gesture only when `Motion.enabled`.

verdict: changes requested

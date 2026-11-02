BUILD round 1
Ticket: all five criteria are met in code. The Linux gate is green. The SwiftUI parts, the `BudStore` tests and the pictures have not been compiled or run, because they build only on the macOS runners.
- Model: met.
  - `inboxID`, `Bud.source`, `Tree.capture`, `Tree.inbox` and `Tree.move` are in `Sources/BudKit/Tree.swift`. `move` returns a Bool. It refuses a move under itself, under its own descendant, or of an unknown bud or parent, and a refused move changes nothing.
  - Old files load with `source` as nil.
  - `walk(under: rootID)`, `today`, `openTodos` and `pinned` ignore inbox buds.
  - `TreeSearcher` includes them with the trail "Inbox".
- Store: met, but not run.
  - `BudStore.capture` and `BudStore.move` are written with the specified toasts. Undo removes the capture, or moves the bud back to its old parent, placed after that parent's last child.
  - A refused move posts no toast.
  - The source word comes from `BudStore.platformSource`.
  - The store tests sit behind `canImport(SwiftUI)`, not `canImport(Combine)`, because `BudStore` itself is behind SwiftUI.
- Capture sheet: met, but not compiled.
  - `AddSheet` now takes a `mode` (enrich or capture). Capture is titled "Capture", has the caption "Lands in the Inbox. Give it a home later.", and has no Kind row. Return captures.
  - Add here in the top bar opens the capture sheet. The hub button reads "Capture".
  - The + on an ordinary card and N under a lit ordinary card still enrich. N when the hub is lit, or when nothing is lit and the center is the hub, captures.
  - The pictures `sheet-capture-light.png`, `sheet-capture-dark.png` and `inbox-light.png` have not been rendered. The snapshot tests that write them are added, and they run only on macOS with the snapshot directory set.
- Sidebar and Inbox page: met, but not compiled.
  - The Inbox place shows its count. Selecting it shows the new `Files/InboxPage.swift`: title, "from <source>" caption, reading order, and a Move to… button per row.
  - Move to… opens `Files/MoveToPicker.swift`: a search field over Everything and every bud, excluding the moving bud and its branch. Return or a click moves there, and the arrow keys change the pick.
  - The palette's Inbox destination now opens the page. This was not asked for.
- Seed: met. `Tree.seed()` has two captures with `source: "mac"`, and a seed test covers them.

Changed: `Sources/BudKit/Tree.swift`, `BudStore.swift`, `Sheets.swift`, `BudRootView.swift`, `OrbitCanvas.swift`, `CardView.swift`, `Files/Sidebar.swift`, `Files/FilesView.swift`, `Files/InboxPage.swift` (new), `Files/MoveToPicker.swift` (new), `Palette/Searcher.swift` (adds `MoveTargets`), `Palette/CommandPalette.swift`, `Tests/BudKitTests/InboxTests.swift` (new), `Tests/BudKitTests/CaptureStoreTests.swift` (new), `Tests/BudKitTests/LayoutTests.swift`, `Tests/BudKitSnapshots/SnapshotTests.swift`.

Tests:
- `InboxTests` has 10 tests:
  - capture lands in the Inbox with its source;
  - inbox buds stay out of the root walk and the lenses;
  - search trail is "Inbox";
  - move re-parents the whole branch after the last child;
  - move to the root;
  - move refused under itself or a descendant, and for an unknown bud or parent;
  - old files decode with a nil source and a source survives a save;
  - move targets;
  - the seed's two captures.
- `CaptureStoreTests` covers trim, blank refusal, toast text, undo, move with its toast and undo, and a refused move. It has not been run here.
- I changed three existing tests in `LayoutTests.swift`. They compared the canvas card count with `tree.buds.count + 1`, and one looped over all buds. Inbox buds are not on the canvas, so they now use `tree.walk(under: rootID)`. The first also asserts that no inbox bud has a card. Nothing was weakened.
- Gate, from the repo root: `swift build` passed, `swift test` passed (37 XCTest tests, 0 failures), `cargo fmt --all --check` was clean, `cargo clippy --all-targets -- -D warnings` was clean, `cargo test --workspace` passed.

Verify:
1. Run `swift test` on Linux or macOS.
2. On the draft pull request, check that the iOS and macOS build checks are green.
3. On macOS, run the snapshot tests with the snapshot directory set and look at `sheet-capture-*.png`, `inbox-*.png` and `canvas-hub-*.png`. The hub should read "Capture".
4. In the app, press Add here and type a line. The toast should read "Captured to the Inbox". Open Files and then Inbox, and the new line should be in the list with "from mac". Press Move to…, search, and press Return. The toast should read "Moved to <title>", and Undo should put it back.

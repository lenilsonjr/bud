BUILD round 1

Ticket:
- `ButtonStyles.swift`, four styles: met in code, not compiled here. `.budPrimary`, `.budSecondary`, `.budGhost` and `.budDestructive` share one style with these measures:
  - label: 13 pt semibold (the `cardTitle` role)
  - radius 8
  - padding 7 pt vertical, 12 pt horizontal
  - pressed state at 85% opacity
  - secondary has the 1 pt `lineStrong` stroke
  - `BudButtonLabel` adds the optional 14 pt icon.
  - The colours were already in `Palette` and `Theme` with the right light and dark values, so I added none.
- `buttons-light.png` and `buttons-dark.png`: partial. `testRendersTheFourButtons` in the snapshot tests writes both with the four styles in a row. The pictures need a macOS run, so none exist yet.
- `Modal.swift`: met in code, not compiled here.
  - `BudStore.modal: Modal?` is an enum with `.add(parent:)` and `.capture`. `.closeBranch` is left for BUD-27.
  - `BudRootView` overlays `ModalHost` over the whole window.
  - The scrim is `Theme.scrim`, and a click on it closes the modal.
  - The card has the `raised` fill, a 1 pt `lineStrong` stroke, radius 22 and padding 24. Its width is 480, or the window width minus 32 when the window is narrower.
  - It appears with a scale from 0.96 and opacity over 0.18 s.
  - On a compact iOS width the card sits at the bottom edge, above the safe area.
  - Esc closes through the Cancel button's cancel shortcut, and Return does Add or Capture through the default-action shortcut.
- Quick add and capture sheets: met in code, not compiled here.
  - Both are shown through `store.modal`, not `.sheet`.
  - The + on a card, N, the detail card's enrich button, the hub's Capture and the bar's Add here all set `store.modal`.
  - Cancel is `.budSecondary` and Add or Capture is `.budPrimary`. An `Esc` keycap sits at the left of the actions row.
  - The bar's Add here also moved to `.budSecondary` with the icon label.
  - `AddTarget` is removed.
- `sheet-add-*.png` and `sheet-capture-*.png`: partial. The snapshot tests now render the whole window with the modal open, but I could not render them here.
- Command palette: met. I did not touch its overlay or `CommandPalette`.

Changed: `Sources/BudKit/ButtonStyles.swift` (new), `Sources/BudKit/Modal.swift` (new), `Sources/BudKit/BudRootView.swift`, `Sources/BudKit/Sheets.swift`, `Sources/BudKit/OrbitCanvas.swift`, `Sources/BudKit/TopBar.swift`, `Sources/BudKit/BudStore.swift`, `Tests/BudKitTests/ModalTests.swift` (new), `Tests/BudKitSnapshots/SnapshotTests.swift`.

I did not change `Palette.swift` or `Theme.swift`, because the tokens were already there.

Tests:
- `ModalTests` runs on Linux and has 6 tests: hub add maps to capture, modal identity, card width 480 or window minus 32, card metrics, button metrics, button and scrim colours.
- Snapshot tests: I updated the two sheet pictures to render the window with the modal open, and added one for the four buttons. They skip unless `BUD_SNAPSHOT_DIR` is set and run on macOS only.
- Gate: `swift build` passed, `swift test` passed (0 failures), `cargo fmt --all --check` was clean, `cargo clippy --all-targets -- -D warnings` was clean, and `cargo test --workspace` passed.
- The SwiftUI files (`ButtonStyles`, `ModalHost`, `Sheets`, `BudRootView`, `OrbitCanvas`, `TopBar`) are not compiled on Linux. The iOS and macOS CI builds on the draft PR are the first compile of them.

Verify:
- On macOS, run the snapshot tests with `BUD_SNAPSHOT_DIR` set and look at `buttons-*.png`, `sheet-add-*.png` and `sheet-capture-*.png`.
- In the app, try each entry point: Add here in the bar, the + on a card, N, and the hub's Capture.
- Each should dim the whole window and show the card in the middle.
- Esc and a click on the scrim should close it, and Return should add.
- On iPhone width, the card should sit at the bottom edge.
- Cmd-K should still show the palette as before.

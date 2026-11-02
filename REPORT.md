BUILD round 1
Ticket:
- Sidebar collapses in portrait, shows in landscape, and a bar button toggles it: **met in code**, not checked on a device. The decision logic is tested on Linux. The SwiftUI wiring compiles only on the macOS CI, and I did not run it.
- ⌘K, N, Space and Esc with a hardware keyboard: **met, no change needed**. `BudRootView.swift` and `OrbitCanvas.swift` already bind them with `.keyboardShortcut` and `.onKeyPress`.
- Trackpad hover moves the light and touch falls back to the last tap: **met, no change needed**. `OrbitCanvas.swift` already uses `onContinuousHover` and the last-tap fallback.
- Layout at 320, 600 and 1024 pt without clipping: **partial**. The collapsing sidebar means a 600 pt window gets the page alone (the sidebar needs 700 pt or more). Widths under about 600 pt get the existing phone layout from the size class. I made no other layout changes and took no screenshots, so clipping at 320 pt is unverified.

Changed:
- `Sources/BudKit/SidebarVisibility.swift` (new): the sidebar rule. It is shown when the window is landscape and at least 700 pt wide. The button's choice lasts until the device turns the other way.
- `Sources/BudKit/BudStore.swift`: added the `sidebar` and `surfaceSize` properties.
- `Sources/BudKit/Files/FilesView.swift`: the sidebar and divider now show only when the rule says so, and the view reports its size to the store.
- `Sources/BudKit/TopBar.swift`: a sidebar toggle button on iOS, shown only in Files on a regular-width window.
- `Tests/BudKitTests/SidebarVisibilityTests.swift` (new).

Tests:
- Five new tests:
  - shown in landscape, collapsed in portrait;
  - a narrow landscape window stays collapsed;
  - the toggle flips the state in both orientations;
  - turning the device clears the button's choice;
  - resizing within one orientation keeps the choice.
- `swift build`: pass.
- `swift test`: pass, 105 tests, 0 failures.
- `cargo fmt --all --check`: pass.
- `cargo clippy --all-targets -- -D warnings`: pass.
- `cargo test --workspace`: pass.
- I did not run the iOS and macOS app builds. That is for the CI on the draft pull request.

Verify:
- On an iPad simulator, open Files in landscape. The sidebar should show, and the sidebar button in the top bar should hide and show it.
- Rotate to portrait. The sidebar should collapse, and the button should bring it back.
- Rotate again. The button's choice should reset to the orientation default.
- Check the 320, 600 and 1024 pt Stage Manager widths for clipping.
- With a hardware keyboard on the canvas, try ⌘K, N, Space and Esc. With a pointer, hover to move the light.

BUILD round 2

Applied:
- **2. Dialog files:** deleted `Sources/BudKit/Devices/RemoveDeviceDialog.swift` and `RotateKeyDialog.swift`. They belong to BUD-90.
- **3. Modal support:** `Sources/BudKit/Modal.swift` keeps only `showTicket` and `joinVault`. `removeDevice`, `rotateKey`, the id-hashing helper and `DeviceModalView` are gone. `ModalHost` and the Mac Settings sheet in `Sources/BudKit/Settings/SettingsView.swift` route straight to `TicketSheet` and `JoinSheet`.
- **4. Toast:** removed the toast, the `.task { devices.start() }` call in `Sources/BudKit/BudRootView.swift`, and `DevicesText.arrived` with its test. The section's own refresh still loads the list.
- **5. Toast and Undoable:** `Sources/BudKit/Toast.swift` and `Undoable.swift` are back to their `develop` content.
- **6. Dialog support in `Sources/BudKit/DeviceStore.swift`:**
  - Removed the rotation `reports` field, the early provisional rotation, the `DevicesText` rotation lines, result and count helpers, and their tests.
  - Kept `rotatedAt`, because the G3 notice reads it, and `relay`. They keep their tests.
- **7. iPad name:** the row now takes "This Mac / iPhone / iPad" from the platform, not from the stored kind. `DeviceStore.shared` no longer sets a kind, so iPad reads "This iPad".
- **7. Why `BudStore.devices` exists:** Settings is drawn from `ModalHost` and `BudRootView`, which hold only a `BudStore`. The section needs a `DeviceStore`, so `BudStore` carries one and a test or picture can inject its own. `DeviceStore.shared` is a stand-in with this device alone until a real node is plugged in.
- **Remove button:** the row still has the Remove action the ticket asks for. `DevicesSection` takes an `onRemove` closure that does nothing for now; BUD-90 wires the dialog in. The button is therefore inert on this branch.

Declined:
- **1. CI `gate` failure:** I could not reproduce it. `.github/workflows/gate.yml` runs the same five steps as the box gate (build, test, fmt, clippy, cargo test), and all pass here. The CI job uses a different Swift toolchain, so a compiler difference is possible. This round removed the most code that only compiles on Linux (dialog support in `Modal.swift` and `DeviceStore.swift`), so a re-run on the new head should show whether it is fixed. Please read that log.
- **8. Wording checked against G1 to G3 and G9:** I cannot read the frames. The section caption, the invitation and the Relay caption are still my wording, in sentence case with no em dash, and need a person to compare them with the board.
- **9. Snapshots:**
  - They are macOS-only. The `snapshots` job in `.github/workflows/build-check.yml` sets `BUD_SNAPSHOT_DIR` and uploads them as an artifact on the pull request.
  - No devices: `settings-light` and `settings-dark`, as before.
  - With devices and one missed: `settings-devices-*` and `settings-missed-*`, each in light and dark.
  - Nothing was rendered here.

Tests:
- `swift build`: passed.
- `swift test`: passed, no failures.
- `cargo fmt --all --check`: passed.
- `cargo clippy --all-targets -- -D warnings`: passed.
- `cargo test --workspace`: passed.
- The SwiftUI files and the three app builds were not compiled here; CI builds them on the pull request.

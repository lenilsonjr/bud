BUILD round 1
Ticket:
- **DEVICES section in `SettingsView` after Vault, with invitation (G1, G9): partial.** The section, the invitation, the two ways in and the platform device word are built. On iPhone and iPad the two ways in stack full width. The caption and invitation text are my wording, because I could not read the `product.pen` frames. A person needs to check those strings and the measures against G1 to G3 and G7 to G9.
- **`DeviceRow`: partial.**
  - Built: reach icon, short id, "This Mac" / "This iPhone" / "This iPad" first, seen label, Remove, the `missed` variant ("Missed the new key", "Pair again") and no action on this device. Long press or right click opens the same actions as a system context menu, like the bud menu.
  - Not checked: the symbols, spacing and colours are not checked against the Device row specimen.
- **G3 notice line: met.** It reads "New key since 10:42. 1 device missed it and needs a fresh ticket." and is plural-aware. It shows only while a device is marked missed. The time comes from `DeviceStore.rotatedAt`, set when a rotation leaves devices behind. Without a time it reads "New key. …".
- **Relay control: partial.** Three choices (Public relays, Custom by URL, Off) are bound to `DeviceStore.relay` and `setRelay`. Custom shows a URL field that applies on submit, and only http or https URLs with a host are accepted. The caption is my wording.
- **Remove (G7) and Rotating the key (G8) dialogs: partial.**
  - Built through the kit's modal, with two new cases `removeDevice(id:)` and `rotateKey` that the ticket did not name.
  - The remove dialog has two choices, with "Remove and rotate the key" as the default, and Cancel and Remove.
  - The rotate dialog shows one line per reported device, the "2 of 3" count and the result line with Done, or a single progress line when the core reports only the result.
  - The sentence in the remove dialog is my wording.
- **`showTicket` / `joinVault` modals with stub views: met.** `TicketSheet.swift` and `JoinSheet.swift` show only their title.
- **G2 toast: met.** `BudRootView` shows "3 changes arrived" after a sync that brought changes. The count is `ops`, or created + updated + moved when `ops` is 0, and a sync with no changes shows nothing. The toast has no Undo (`Undoable.offersUndo`).
- **Existing pictures unchanged except `settings-light` and `settings-dark`: partial.** `ToastView` is unchanged for existing toasts. Nothing was run to compare pictures here. I added snapshot tests that write `settings-devices-*` and `settings-missed-*`.

Also added, not asked for:
- `BudStore.devices`, defaulting to `DeviceStore.shared`, which holds this device alone for now.
- The Mac Settings window has no modal of its own, so it shows the same dialogs as sheets.

Changed:
- New: `Sources/BudKit/Devices/DevicesText.swift`, `DeviceRow.swift`, `DevicesSection.swift`, `RemoveDeviceDialog.swift`, `RotateKeyDialog.swift`, `TicketSheet.swift`, `JoinSheet.swift`
- Edited: `Sources/BudKit/Settings/SettingsView.swift`, `Modal.swift`, `BudRootView.swift`, `BudStore.swift`, `DeviceStore.swift`, `Toast.swift`, `Undoable.swift`
- Tests: `Tests/BudKitTests/DevicesTextTests.swift` (new), `DeviceStoreTests.swift`, `Tests/BudKitSnapshots/SnapshotTests.swift`

Tests:
- `DevicesTextTests` (13 tests) covers:
  - this-device names, the device word, ordering and the empty list
  - the notice line, the "N changes arrived" text and the rotation count and lines
  - the result line, the relay choices and URL check, and distinct modal identities
- `DeviceStoreTests` gained 4 tests: reports per device, `rotatedAt`, no time without rotation, and relay read and write.
- Snapshot test `testRendersSettingsWithDevices` is macOS-only and skipped here.
- Gate, each from the repo root:
  - `swift build`: passed.
  - `swift test`: passed.
  - `cargo fmt --all --check`: passed.
  - `cargo clippy --all-targets -- -D warnings`: passed.
  - `cargo test --workspace`: passed.
- The SwiftUI files do not compile on Linux. The macOS and iOS CI checks on the draft pull request are the first compile of them.

Verify: open Settings (⌘, on Mac, the gear on iPhone and iPad). With no other device you should see DEVICES with the invitation, "Show a ticket" and "Add this Mac to a vault" (full width and stacked on iOS), and the Relay control at the foot. With paired devices you should see the list, this device first. A device that missed a key shows the notice line, "Missed the new key" and "Pair again". Remove opens G7. Choosing Remove and rotate opens G8, which lists each device and ends on the result with Done. Compare every string and measure with the board frames. Snapshots come from running the snapshot tests with `BUD_SNAPSHOT_DIR` set on a Mac.

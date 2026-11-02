```
REVIEW round 1
Reviewed: crew/BUD-82 against develop
What this does: Adds a DEVICES section to Settings with the invitation, `DeviceRow`, the G3 notice line, the Relay control and the two new `Modal` cases with stub ticket and join sheets. It also carries the two dialogs, a sync toast and an `Undoable` change. The operator's follow-up moved those three to BUD-90.

Ticket check:
- DEVICES section and invitation: partial. The caption and invitation wording is the builder's own because the frames were not read, and the report says so.
- `DeviceRow`: partial. The report says its symbols, spacing and colours were not checked against the specimen.
- G3 notice line: met on the code read. No snapshot was run.
- Relay control: partial. The caption is the builder's own wording.
- `showTicket` and `joinVault` modals with stubs: met.
- Dialogs, toast and `Undoable` change: beyond the narrowed ticket. The operator said to take them off this branch for BUD-90, and they are still here.
- Existing pictures unchanged except `settings-light` and `settings-dark`: unverified. Nothing was compared, and the new snapshot is macOS-only.

Tests:
- CI: the check on head 473524257b16 failed. `gate` is the failing job. The log was not readable here, so I cannot say which step failed. A failing required check means changes requested. The report does not mention the iOS, macOS and tvOS build checks, so I have no result for them.
- Run here: `swift build` passed. `swift test` ran with no failures. I did not run the cargo steps, because the verdict is already set by the failing CI check.
- Coverage: `DevicesTextTests` and four new `DeviceStoreTests` cover the pure state. No test covers the new `DeviceStore` behaviour (`rotatedAt`, `reports`, `relay`) apart from those four.
- Gap: all the SwiftUI files are uncompiled and unrendered on this box. The ticket's snapshot pictures for no devices, with devices and with a missed device, in light and dark, were not produced or checked in.

Findings:
1. CI `gate` bug: the required `gate` check failed on this head, and the builder's report says every gate step passed. Reproduce `gate` from the repository's CI definition and fix whatever it reports. I can't say what fails from here. Possible causes are the Rust steps and a format or lint step that differs from the box gate. Re-push and confirm that `gate` and the three app builds are green.
2. Sources/BudKit/Devices/RemoveDeviceDialog.swift, Sources/BudKit/Devices/RotateKeyDialog.swift design: the operator narrowed the ticket and told the builder to take these dialog files off the branch. They are still here and need removing. They belong to BUD-90.
3. Sources/BudKit/Modal.swift:11-37 design: `removeDevice(id:)`, `rotateKey` and the hashing `identity(of:)` helper are dialog support and go with the dialogs. Only `showTicket` and `joinVault` stay. The report admits the two dialog cases were never named in the ticket. The `ModalHost` branch that routes them goes too, which includes `DeviceModalView`.
4. Sources/BudKit/BudRootView.swift:50-53 design: the toast and the `.task { await store.devices.start() }` are out of scope. Remove the toast. The `start()` call is the builder's addition and needs its own justification if it stays. Also remove `DevicesText.arrived`, with its tests.
5. Sources/BudKit/Toast.swift:62 and Sources/BudKit/Undoable.swift: the narrowed ticket put any Undoable change on BUD-90. Revert both files. `ToastView` changes could also move existing pictures.
6. Sources/BudKit/DeviceStore.swift:183-205 design: the rotation `reports` field and the `remove` reordering are dialog support. Remove them and their tests from this branch. The reorder also publishes a provisional `RotationProgress` before the removal finishes. Keep `rotatedAt` only if the G3 notice needs it.
7. Sources/BudKit/DeviceStore.swift:70-73 question: `DeviceStore.shared` is a static stand-in that holds only this device, built with `isPad: false`. On iPad the row would read "This iPhone" if the stored kind is used. Does the row take its name from the platform instead? Also say why the box needs a store of its own and `BudStore.devices` at all, since the ticket says the section reads from `DeviceStore`.
8. Sources/BudKit/Devices/DevicesSection.swift question: the caption, invitation and Relay caption were written without the frames. Someone should check them against G1 to G3 and G9, and against the sentence case and no em dash rule. I could not confirm them.
9. Tests/BudKitSnapshots/SnapshotTests.swift nit: the new snapshots are macOS-only and unrun. Say how a reviewer or CI sees them. The ticket needs pictures for no devices, with devices and with a missed device, in light and dark, and the report names only `settings-devices-*` and `settings-missed-*`.

verdict: changes requested
```

```
REVIEW round 2
Earlier findings:
1. CI `gate` failure: addressed. The checks on head 4fb0aca001935fee7b7a48a6589e67d67086660d passed (5 checks). The builder could not reproduce the failure and it cleared on the new head.
2. Dialog files: addressed. `RemoveDeviceDialog.swift` and `RotateKeyDialog.swift` are no longer in the diff.
3. Modal support: addressed. `Modal.swift` changes are small, and the diff has no dialog cases.
4. Toast, `start()` call and `DevicesText.arrived`: addressed. `BudRootView.swift` is no longer in the diff.
5. `Toast.swift` and `Undoable.swift`: addressed. Neither is in the diff.
6. Dialog support in `DeviceStore`: addressed. `rotatedAt` and `relay` stay, which my finding allowed for the notice.
7. iPad name and the `BudStore.devices` question: addressed. The row takes its device name from the platform, and the builder gave a reasonable reason for the `BudStore.devices` stand-in.
8. Wording not checked against the frames: partial. The builder declined because the frames are unreadable to it, and that is a reasonable decline. Someone with the board still has to check the caption, invitation and Relay caption wording against G1 to G3 and G9.
9. Snapshots: addressed. The builder named the CI job that renders them. They are not seen here and need a look when they come.
New: The Remove button on rows is inert on this branch, because `onRemove` does nothing until BUD-90 wires the dialog. This follows from the narrowing and the builder said so. It is not a blocker.
Tests: CI passed all 5 checks on this head, so I ran nothing myself. I read the diff stat and the report only.
verdict: approved
```

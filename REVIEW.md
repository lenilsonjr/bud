I've run the whole box gate and found the likely cause of the failing builds. I'm writing the verdict now.

REVIEW round 1
Reviewed: crew/BUD-52 against develop
What this does: It adds the four kit button styles (`ButtonStyles.swift`) and a modal presenter (`Modal.swift`). `BudStore.modal` drives a scrim and a raised card that `BudRootView` overlays on the window. The quick add and capture sheets move from `.sheet` onto it, with Cancel as `.budSecondary`, Add or Capture as `.budPrimary`, and an Esc keycap at the left of the actions row. The change does not compile on the app targets.

Ticket check:
- Four button styles: partial. The measures look right in the code, but the target does not compile. `buttons-light.png` and `buttons-dark.png` do not exist.
- `Modal.swift` and `BudStore.modal`: partial. The design matches the ticket, but nobody has compiled it, and the scrim, card and compact placement are unseen.
- Sheets through the modal, with the Esc keycap: partial. The entry points all go through `store.modal`, but the keycap added in `Sheets.swift` collides with an existing type.
- Palette unchanged: met. The overlay was not touched.
- Pictures (`sheet-add-*`, `sheet-capture-*`): missing. Nothing was rendered.
- `Palette.swift`, `Theme.swift`, snapshot tests: the colours were already there, so no change was needed, which is fine.

Tests:
- Box gate, run by me from `work`:
  - `swift build`: passed.
  - `swift test`: passed. 45 tests ran, including 6 in `ModalTests`.
  - `cargo fmt --all --check`: clean.
  - `cargo clippy --all-targets -- -D warnings`: clean.
  - `cargo test --workspace`: passed.
- CI on `f8b6f9320586093084ffbbf6363dd8d9a7c6c822` failed on `build (iOS, Bud iOS, generic/platform=iOS)`, `build (macOS, Bud macOS, generic/platform=macOS)` and `snapshots`. A failing required check is a failing gate.
- The Linux gate cannot see the failure, because every file the diff touches except `Modal.swift`'s metrics sits behind `#if canImport(SwiftUI)`.
- `ModalTests` covers only metrics and colours. Nothing tests the host, the dismissal or the Return and Esc behaviour. That is acceptable for SwiftUI code once the build is fixed.

Findings:
1. Sources/BudKit/Sheets.swift:102 bug: `struct Keycap` is declared again. `Sources/BudKit/TopBar.swift:136` already declares `struct Keycap` with the same `init(_:)`, and `CommandPalette.swift:35` and `TopBar.swift:108` use it. Two internal types with one name in one module is an "invalid redeclaration" error, so the iOS and macOS builds fail, and the `snapshots` job with them. The fix is to delete the new `Keycap` from `Sheets.swift` and use the existing one for the Esc chip. If the kit's Esc chip needs a different look, give the existing one a parameter instead of adding a second type.
2. Sources/BudKit/Sheets.swift:63 design: the Esc keycap at the left of the actions row is correct, but its look changes with finding 1. Once the build is green, check against the kit that the chip still reads right.
3. Sources/BudKit/Modal.swift:52 question: `.id(modal)` sits on the card's `GeometryReader`, and the scrim is outside it. When one modal replaces another, such as add under a card and then capture, the card re-creates but the scrim does not. Is that intended? It cannot be judged until the code compiles and the pictures exist.
4. Tests/BudKitSnapshots/SnapshotTests.swift:209 nit: the two sheet tests set `store.modal` and call `render(store:scheme:)`. Nothing shows that the overlay is drawn at render time, since the appear transition and animation may leave the first frame empty. Confirm the picture shows the dimmed window and the card once the build is green. The 10 kB size floor is a weak proxy for that.
5. Pictures missing, all four: `buttons-*.png`, `sheet-add-*.png`, `sheet-capture-*.png`. The `snapshots` check failed, so none were produced. Once the redeclaration is fixed, re-run the checks and look at the pictures before approval.

verdict: changes requested

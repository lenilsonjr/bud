# Bud · SwiftUI prototype

A bare-bones native port of the orbit canvas: buds that are notes or to-dos, nested without limit,
on a flat web of orbits you drag around. No warehouses, no triggers.

- `Sources/BudKit` — the package. `Tree.swift` (model), `Layout.swift` (the wedge-based orbit
  layout) and `Palette.swift` (colour tokens, radii, type scale) are pure Swift and run anywhere;
  the SwiftUI views and `Theme.swift` sit beside them. `Resources/Fonts` holds Fraunces, Figtree
  and JetBrains Mono with their OFL licences; `Theme` registers them at runtime.
- `Sources/BudMac` — a macOS runner so the canvas works without an Xcode project.
- `Tests/BudKitTests` — model, layout and theme tests; they run on Linux too.
- `Tests/BudKitSnapshots` — renders the canvas to PNGs when `BUD_SNAPSHOT_DIR` is set (macOS only);
  every pull request attaches them as an artifact.
- `Tests/BudCatalogIOS` — the phone and iPad shots of the screen catalog, drawn by the iOS app on
  a simulator; unit tests hosted in the app (the `Bud iOS Catalog` scheme); pictures to look at,
  never compared.
- `App` + `project.yml` — a thin multiplatform app (iOS, iPadOS, macOS, tvOS) that hosts
  `BudRootView` from `BudKit`, or `BudTVView` on Apple TV: the same orbit canvas with the
  remote moving the light from card to card, one line of capture, Play/Pause to tick a to-do.
  The Xcode project is generated, never committed.
- `core/bud-core` — the Rust core. A vault is a folder of Markdown files; the crate walks it into a
  SQLite index kept outside the vault and answers the queries the views need. The files are the
  only truth; the index is disposable.

## Run

```sh
swift run BudMac          # the macOS runner, no Xcode project needed
swift test                # model + layout tests (run on Linux too)
cargo test --workspace    # the Rust core's tests
scripts/compare-screens.sh develop   # which screens moved since develop (macOS); no ref: since the last release
scripts/ios-catalog.sh "iPad Pro 13-inch (M4)"   # the iOS catalog of the working tree, into build/screens-ios
```

For the real apps, build the Rust core, then generate the Xcode project (needs rustup and
[XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
scripts/build-core.sh     # build/BudCoreFFI.xcframework and the Swift bindings
xcodegen generate
open Bud.xcodeproj         # schemes: "Bud iOS", "Bud macOS"
```

`Bud.xcodeproj` is derived from `project.yml` and git-ignored. Both app targets depend on the local
`BudKit` package and share one `@main` entry (`App/BudApp.swift`); the model, layout, and views are
`BudKit`'s, never copied. Requires macOS 14 / iOS 17 (Swift 5.9+). The apps keep the vault, a
folder of Markdown files, in their `Documents/Bud` (the Apple TV's in Caches), with the index beside
the app's support files. `swift run BudMac` still saves to `buds.json` in Application Support.

Touch: drag to move, pinch to zoom, tap a card with children to center it, tap a leaf to edit, the
trail at the top steps back out. On iPad and Mac the light follows the pointer.

## TestFlight

Push a `v*` tag → GitHub Actions builds, signs, and ships **iOS, macOS and tvOS** to TestFlight
internal testers (marketing version = the tag), so every TestFlight build is a deliberate release you
can write a changelog for. Merges to `develop` run only a compile-only check (`build-check.yml`) — they
don't ship on their own; you can also trigger a build by hand from the Actions tab.

Signing is manual, with one shared Apple Distribution certificate (plus the Mac installer certificate
for the `.pkg`) and an App Store profile per platform. They live as an encrypted bundle in object
storage that CI fetches with a read-only key and imports into a throwaway keychain, so a fresh runner
never asks Apple for a certificate. `scripts/bootstrap-signing.py` creates and uploads that bundle once;
`scripts/setup-secrets.sh` sets the secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
`APPLE_TEAM_ID`, `BUNDLE_ID_PREFIX`, `B2_SIGNING_KEY_ID`, `B2_SIGNING_APP_KEY`, `B2_SIGNING_ENDPOINT`,
`B2_SIGNING_BUCKET`, `SIGNING_PASSPHRASE`). The App Store Connect API key is still what uploads the
build. See `.github/workflows/` and `fastlane/`.

## App icon

A blue-amethyst leaf on a leaf→moss gradient with film grain. The live icon is the classic asset
catalog at `Resources/Assets.xcassets/AppIcon.appiconset`, which covers every OS version:

- **iOS / iPadOS** — one 1024 master plus **dark** and **tinted** appearances (iOS 18+; the system
  renders the tint from a greyscale master). Masters are square and opaque; iOS masks the corners.
- **macOS** — the full 16–512 pt set at @1x/@2x, rounded-rect shape and shadow baked in (macOS before
  26 does not mask), grain only from 128 pt up.
- **Accent** — `AccentColor` is the amethyst, lavender in dark mode.

`ASSETCATALOG_COMPILER_APPICON_NAME` / `…_GLOBAL_ACCENT_COLOR_NAME` are set to `AppIcon` / `AccentColor`
in `project.yml`.

Design assets live in `Design/` (not compiled): `Bud.icon` is the Icon Composer / Liquid Glass source
for the iOS 26 / macOS 26 upgrade, `marketing-icon-1024.png` is the opaque App Store marketing icon,
and `Marks/` has the leaf alone as SVG (amethyst, lavender, white, black). To adopt Liquid Glass later,
add `Bud.icon` to the targets and point `ASSETCATALOG_COMPILER_APPICON_NAME` at `Bud` — but keep the
`AppIcon` set while iOS 17 / macOS 14 are supported.

## Status

Early prototype. The model and layout are covered by tests and build on Linux as well as macOS.
The SwiftUI views target macOS 14 and iOS 17 and are still being shaken out on device. tvOS and a
watch companion are planned once the canvas has a focus-engine / small-screen interaction model.

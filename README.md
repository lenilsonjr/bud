# Bud · SwiftUI prototype

A bare-bones native port of the orbit canvas: buds that are notes or to-dos, nested without limit,
on a flat web of orbits you drag around. No warehouses, no triggers.

- `Sources/BudKit` — the package. `Tree.swift` (model) and `Layout.swift` (the wedge-based orbit
  layout) are pure Swift and run anywhere; the SwiftUI views sit beside them.
- `Sources/BudMac` — a macOS runner so the canvas works without an Xcode project.
- `Tests/BudKitTests` — model and layout tests; they run on Linux too.
- `App` + `project.yml` — a thin multiplatform app (iOS, iPadOS, macOS) that hosts `BudRootView`
  from `BudKit`. The Xcode project is generated, never committed.
- `core/bud-core` — the Rust core. A vault is a folder of Markdown files; the crate walks it into a
  SQLite index kept outside the vault and answers the queries the views need. The files are the
  only truth; the index is disposable.

## Run

```sh
swift run BudMac          # the macOS runner, no Xcode project needed
swift test                # model + layout tests (run on Linux too)
cargo test --workspace    # the Rust core's tests
```

For the real apps, generate the Xcode project (needs [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
xcodegen generate
open Bud.xcodeproj         # schemes: "Bud iOS", "Bud macOS"
```

`Bud.xcodeproj` is derived from `project.yml` and git-ignored. Both app targets depend on the local
`BudKit` package and share one `@main` entry (`App/BudApp.swift`); the model, layout, and views are
`BudKit`'s, never copied. Requires macOS 14 / iOS 17 (Swift 5.9+). Data is saved to
`~/Library/Application Support/Bud/buds.json`; delete it to get the seed world back.

Touch: drag to move, pinch to zoom, tap a card with children to center it, tap a leaf to edit, the
trail at the top steps back out. On iPad and Mac the light follows the pointer.

## TestFlight

Push to `develop` → GitHub Actions builds, signs, and ships **iOS and macOS** to TestFlight internal
testers (auto build number). A `v*` tag on `main` ships a release build (marketing version = the tag).
Pull requests run a compile-only check. Signing is cloud-managed via an App Store Connect API key — no
certificate files — driven by the repo/org secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
`APPLE_TEAM_ID`, `BUNDLE_ID_PREFIX`. See `.github/workflows/` and `fastlane/`.

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

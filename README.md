# Bud · SwiftUI prototype

A bare-bones native port of the orbit canvas: buds that are notes or to-dos, nested without limit,
on a flat web of orbits you drag around. No warehouses, no triggers.

- `Sources/BudKit` — the package. `Tree.swift` (model) and `Layout.swift` (the wedge-based orbit
  layout) are pure Swift and run anywhere; the SwiftUI views sit beside them.
- `Sources/BudMac` — a macOS runner so the canvas works without an Xcode project.
- `Tests/BudKitTests` — model and layout tests; they run on Linux too.

## Run on a Mac

```sh
cd swift/Bud
swift run BudMac
```

Requires macOS 14 and Xcode 15 (or a Swift 5.9+ toolchain). Data is saved to
`~/Library/Application Support/Bud/buds.json`; delete it to get the seed world back.

## Run on iPhone or iPad

1. In Xcode: File › New › Project › iOS App (SwiftUI). Deployment target iOS 17.
2. File › Add Package Dependencies… › Add Local… › choose `swift/Bud`. Add `BudKit` to the app target.
3. Replace the generated `ContentView()` in the `App` struct with:

```swift
import BudKit

@main
struct BudApp: App {
    var body: some Scene {
        WindowGroup { BudRootView() }
    }
}
```

Touch: drag to move, pinch to zoom, tap a card with children to center it, tap a leaf to edit,
use the trail at the top to step back out. On iPad the light follows the pointer.

## Tests

```sh
swift test
```

## Status

Early prototype. The model and layout are covered by tests and build on Linux as well as macOS.
The SwiftUI views target macOS 14 and iOS 17 and are still being shaken out on device.

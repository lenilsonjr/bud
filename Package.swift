// swift-tools-version:5.9
import PackageDescription

// The screen catalog compares pictures only on macOS, where the views render; the manifest is
// read on the host, so Linux resolves nothing it never imports.
#if os(macOS)
let comparator: [Package.Dependency] = [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7"),
]
let comparatorProducts: [Target.Dependency] = [
    .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
]
#else
let comparator: [Package.Dependency] = []
let comparatorProducts: [Target.Dependency] = []
#endif

let package = Package(
    name: "Bud",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "BudKit", targets: ["BudKit"]),
        .executable(name: "BudMac", targets: ["BudMac"]),
    ],
    dependencies: comparator,
    targets: [
        .target(name: "BudKit", resources: [.copy("Resources/Fonts")]),
        .executableTarget(name: "BudMac", dependencies: ["BudKit"]),
        .testTarget(name: "BudKitTests", dependencies: ["BudKit"]),
        .testTarget(
            name: "BudKitSnapshots",
            dependencies: ["BudKit"] + comparatorProducts,
            exclude: ["__Snapshots__"]),
    ]
)

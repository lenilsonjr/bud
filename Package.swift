// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bud",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "BudKit", targets: ["BudKit"]),
        .executable(name: "BudMac", targets: ["BudMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7"),
    ],
    targets: [
        .target(name: "BudKit", resources: [.copy("Resources/Fonts")]),
        .executableTarget(name: "BudMac", dependencies: ["BudKit"]),
        .testTarget(name: "BudKitTests", dependencies: ["BudKit"]),
        .testTarget(
            name: "BudKitSnapshots",
            dependencies: ["BudKit", .product(name: "SnapshotTesting", package: "swift-snapshot-testing")],
            exclude: ["__Snapshots__"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bud",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "BudKit", targets: ["BudKit"]),
        .executable(name: "BudMac", targets: ["BudMac"]),
    ],
    targets: [
        .target(name: "BudKit", resources: [.copy("Resources/Fonts")]),
        .executableTarget(name: "BudMac", dependencies: ["BudKit"]),
        .testTarget(name: "BudKitTests", dependencies: ["BudKit"]),
        .testTarget(name: "BudKitSnapshots", dependencies: ["BudKit"]),
    ]
)

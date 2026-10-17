// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalSecurity",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LocalSecurity", path: "AdminManager/Sources/Services/Privacy"),
        .target(name: "ModelConfiguration", path: "AdminManager/Sources/Services/ModelConfiguration"),
        .target(name: "SystemInventory", path: "AdminManager/Sources/Services/SystemInventory"),
        .testTarget(name: "LocalSecurityTests", dependencies: ["LocalSecurity", "ModelConfiguration"], path: "Tests/LocalSecurityTests"),
        .testTarget(name: "SystemInventoryTests", dependencies: ["SystemInventory"], path: "Tests/SystemInventoryTests", resources: [.copy("Fixtures")]),
    ]
)

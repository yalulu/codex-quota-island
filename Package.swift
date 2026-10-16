// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexQuotaIsland", targets: ["CodexQuotaIsland"]),
    ],
    targets: [
        .executableTarget(name: "CodexQuotaIsland"),
        .testTarget(name: "CodexQuotaIslandTests", dependencies: ["CodexQuotaIsland"]),
    ]
)

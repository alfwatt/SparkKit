// swift-tools-version:6.1

import Foundation
import PackageDescription

// Uses a local sibling checkout if one is present (development), otherwise
// falls back to the git remote (CI, or anyone who hasn't checked it out locally).
func localOrRemote(_ name: String, url: String, from version: Version) -> Package.Dependency {
    let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let localPath = packageDirectory.deletingLastPathComponent().appendingPathComponent(name).path
    if FileManager.default.fileExists(atPath: localPath) {
        return .package(path: localPath)
    }
    return .package(url: url, from: version)
}

let package = Package(
    name: "SparkKit",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15)],
    products: [
        .library(name: "SparkKit", type: .dynamic, targets: ["SparkKit"])
    ],
    dependencies: [
        localOrRemote("KitBridge", url: "https://github.com/alfwatt/KitBridge.git", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "SparkKit",
            dependencies: [
                .product(name: "KitBridge", package: "KitBridge")
            ],
            exclude: ["Info.plist"]
        )
    ],
    swiftLanguageModes: [.v5]
)

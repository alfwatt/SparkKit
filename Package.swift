// swift-tools-version:5.10

import PackageDescription

let package = Package(
	name: "SparkKit",
    platforms: [.macOS(.v10_14), .iOS(.v14), .tvOS(.v14)],
	products: [
		.library( name: "SparkKit", targets: ["SparkKit"])
	],
    dependencies: [
        .package( url: "https://github.com/alfwatt/KitBridge.git", from: "2.3.0")
    ],
    targets: [
        .target( name: "SparkKit", dependencies: ["KitBridge"])
    ]
)

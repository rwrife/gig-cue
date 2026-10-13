// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GigCueKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GigCueKit", targets: ["GigCueKit"]),
    ],
    targets: [
        .target(name: "GigCueKit"),
        .testTarget(name: "GigCueKitTests", dependencies: ["GigCueKit"]),
    ]
)

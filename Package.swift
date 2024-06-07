// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "NetworkKit",
            targets: ["NetworkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ivkuznetsov/CommonUtils.git", from: .init(1, 2, 6))
    ],
    targets: [
        .target(
            name: "NetworkKit",
            dependencies: ["CommonUtils"]),
    ]
)

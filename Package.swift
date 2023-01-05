// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Network",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Network",
            targets: ["Network"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ivkuznetsov/CommonUtils.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Network",
            dependencies: ["CommonUtils"]),
    ]
)

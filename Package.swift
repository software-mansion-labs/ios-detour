// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Detour",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Detour",
            targets: ["Detour"]
        ),
        // A separate product, so an app with Detour alone links no attribution framework and keeps
        // its privacy manifest free of tracking.
        .library(
            name: "DetourAttribution",
            targets: ["DetourAttribution"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Detour",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "DetourAttribution",
            dependencies: ["Detour"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "DetourTests",
            dependencies: ["Detour"]
        ),
        .testTarget(
            name: "DetourAttributionTests",
            dependencies: ["DetourAttribution"]
        ),
    ]
)

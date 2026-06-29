// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipLAN",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClipLANCore", targets: ["PasteCore"]),
        .executable(name: "ClipLAN", targets: ["ClipLAN"])
    ],
    targets: [
        .target(
            name: "PasteCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "ClipLAN",
            dependencies: ["PasteCore"],
            path: "Sources/Paste",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"]
        )
    ]
)

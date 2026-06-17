// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Video2Live",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "Video2Live", targets: ["Video2Live"]),
        .executable(name: "Video2LiveSmoke", targets: ["Video2LiveSmoke"])
    ],
    targets: [
        .target(
            name: "Video2LiveCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Photos"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "Video2Live",
            dependencies: ["Video2LiveCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Photos"),
                .linkedFramework("PhotosUI"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "Video2LiveSmoke",
            dependencies: ["Video2LiveCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Photos"),
                .linkedFramework("PhotosUI")
            ]
        ),
        .testTarget(
            name: "Video2LiveCoreTests",
            dependencies: ["Video2LiveCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)

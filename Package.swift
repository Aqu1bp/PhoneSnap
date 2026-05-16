// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenshotCatch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ScreenshotCatch", targets: ["ScreenshotCatch"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotCatch",
            path: "Sources/ScreenshotCatch"
        )
    ]
)

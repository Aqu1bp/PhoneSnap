// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenshotCatch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ScreenshotCatch", targets: ["ScreenshotCatch"]),
        .executable(name: "ICProbe", targets: ["ICProbe"]),
        .executable(name: "UsbmuxdProbe", targets: ["UsbmuxdProbe"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotCatch",
            path: "Sources/ScreenshotCatch"
        ),
        .executableTarget(
            name: "ICProbe",
            path: "Sources/ICProbe"
        ),
        .executableTarget(
            name: "UsbmuxdProbe",
            path: "Sources/UsbmuxdProbe"
        )
    ]
)

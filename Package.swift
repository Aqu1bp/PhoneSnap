// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneSnap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PhoneSnap", targets: ["PhoneSnap"]),
        .executable(name: "ICProbe", targets: ["ICProbe"]),
        .executable(name: "UsbmuxdProbe", targets: ["UsbmuxdProbe"])
    ],
    targets: [
        .executableTarget(
            name: "PhoneSnap",
            path: "Sources/PhoneSnap"
        ),
        .executableTarget(
            name: "ICProbe",
            path: "Sources/ICProbe"
        ),
        .executableTarget(
            name: "UsbmuxdProbe",
            path: "Sources/UsbmuxdProbe"
        ),
        .testTarget(
            name: "PhoneSnapTests",
            dependencies: ["PhoneSnap"],
            path: "Tests/PhoneSnapTests"
        )
    ]
)

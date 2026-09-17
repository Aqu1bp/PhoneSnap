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
        .systemLibrary(name: "CLibIMobileDevice", pkgConfig: "libimobiledevice-1.0", providers: [.brew(["libimobiledevice"])]),
        .systemLibrary(name: "CUsbmuxd", pkgConfig: "libusbmuxd-2.0", providers: [.brew(["libusbmuxd"])]),
        .executableTarget(
            name: "PhoneSnap",
            dependencies: ["CLibIMobileDevice", "CUsbmuxd"],
            path: "Sources/PhoneSnap",
            linkerSettings: [.linkedLibrary("z")]
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

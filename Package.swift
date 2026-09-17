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
        .systemLibrary(name: "COpenSSL", pkgConfig: "openssl", providers: [.brew(["openssl@3"])]),
        .target(name: "PhoneTCP", dependencies: ["COpenSSL"]),
        .executableTarget(
            name: "PhoneSnap",
            dependencies: ["CLibIMobileDevice", "CUsbmuxd", "PhoneTCP"],
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
            path: "Tests/PhoneSnapTests",
            resources: [.copy("Fixtures/direct_phone_server.py")]
        )
    ]
)

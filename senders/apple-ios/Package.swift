// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneSnapSender",
    platforms: [
        .iOS(.v13),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PhoneSnapSender", targets: ["PhoneSnapSender"])
    ],
    targets: [
        .target(name: "PhoneSnapSender")
    ]
)

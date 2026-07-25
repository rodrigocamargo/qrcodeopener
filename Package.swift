// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QRCodeOpener",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QRCodeOpener",
            path: "Sources/QRCodeOpener"
        )
    ]
)

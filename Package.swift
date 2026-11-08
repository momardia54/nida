// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Nida",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Nida",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")],
            path: "Sources/Nida"
        )
    ]
)

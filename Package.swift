// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Grammy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Grammy",
            path: "Sources/Grammy",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(name: "GrammyTests", dependencies: ["Grammy"]),
    ]
)

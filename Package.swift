// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TCANavigationMap",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0")
    ],
    targets: [
        .executableTarget(
            name: "tca-navmap",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .testTarget(name: "NavigationMapTests", dependencies: ["tca-navmap"])
    ],
    swiftLanguageModes: [.v6]
)

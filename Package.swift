// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AxiosNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0"),
    ],
    targets: [
        .executableTarget(
            name: "AxiosNotch",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/AxiosNotch",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AxiosNotchTests",
            dependencies: ["AxiosNotch"],
            path: "Tests/AxiosNotchTests"
        ),
    ]
)

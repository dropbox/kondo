// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "refactor",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "refactor", targets: ["refactor"]),
        .library(name: "Kondo", targets: ["Buck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0"),
        .package(url: "https://github.com/JohnSundell/ShellOut.git", from: "2.0.0"),
        .package(url: "https://github.com/jpsim/SourceKitten.git", branch: "main"),
        .package(url: "https://github.com/surfandneptune/CommandCougar.git", from: "1.0.0"),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz", from: "0.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "refactor",
            dependencies: [
                "CommandLine",
            ]
        ),
        .target(
            name: "Buck",
            dependencies: [
                "Files",
                "Graph",
                "Parser",
                "Rename",
                "Shell",
                "Utilities",
            ]
        ),
        .target(
            name: "CommandLine",
            dependencies: [
                "Buck",
                "CommandCougar",
                "Files",
                "Graph",
                "Parser",
                "Rename",
                "Utilities",
            ]
        ),
        .target(
            name: "Graph",
            dependencies: [
                "Files",
                "GraphViz",
                "Utilities",
            ]
        ),
        .target(
            name: "Parser",
            dependencies: [
                "Files",
                "Utilities",
                .product(name: "SourceKittenFramework", package: "SourceKitten"),
            ]
        ),
        .target(
            name: "Rename",
            dependencies: [
                "Files",
                "Utilities",
            ]
        ),
        .target(
            name: "Shell",
            dependencies: [
                "Files",
                "ShellOut",
                "Utilities",
            ]
        ),
        .target(
            name: "Utilities",
            dependencies: [
                "Files",
            ]
        ),
        .target(
            name: "TestData",
            dependencies: [
                "Buck",
                "Files",
                "Graph",
                "Parser",
                "Rename",
                "Shell",
            ]
        ),
        .testTarget(
            name: "BuckTests",
            dependencies: [
                "Buck",
                "Files",
                "TestData",
            ]
        ),
        .testTarget(
            name: "CommandLineTests",
            dependencies: [
                "CommandLine",
                "TestData",
            ]
        ),
        .testTarget(
            name: "GraphTests",
            dependencies: [
                "Graph",
                "TestData",
            ]
        ),
        .testTarget(
            name: "ParserTests",
            dependencies: [
                "Parser",
                "TestData",
            ]
        ),
        .testTarget(
            name: "RenameTests",
            dependencies: [
                "Rename",
                "TestData",
            ]
        ),
    ]
)

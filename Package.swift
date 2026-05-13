// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownView",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "MarkdownView", targets: ["MarkdownView"]),
        .library(name: "MarkdownParser", targets: ["MarkdownParser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Ichigo3766/Litext.git", branch: "main"),
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
        .package(url: "https://github.com/apple/swift-collections", branch: "main"),
        .package(url: "https://github.com/smittytone/HighlighterSwift", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.8.0"),
        .package(url: "https://github.com/nicklockwood/LRUCache", branch: "main"),
    ],
    targets: [
        .target(
            name: "MarkdownView",
            dependencies: [
                "Litext",
                .product(name: "Highlighter", package: "HighlighterSwift"),
                "MarkdownParser",
                "SwiftMath",
                "LRUCache",
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "MarkdownParser", dependencies: [
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .testTarget(
            name: "MarkdownParserTests",
            dependencies: [
                "MarkdownParser",
            ]
        ),
    ]
)

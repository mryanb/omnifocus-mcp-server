// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OmniFocusMCPServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "omnifocus-mcp-server", targets: ["OmniFocusMCPServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "OmniFocusMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/OmniFocusMCPServer"
        ),
        .testTarget(
            name: "OmniFocusMCPServerTests",
            dependencies: ["OmniFocusMCPServer"],
            path: "Tests/OmniFocusMCPServerTests"
        ),
    ]
)

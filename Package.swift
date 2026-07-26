// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacDisplayConnect",
    platforms: [
        .macOS("26.0"),
        .visionOS("26.0"),
    ],
    products: [
        .library(name: "MacDisplayConnectCore", targets: ["MacDisplayConnectCore"]),
        .library(
            name: "MacDisplayConnectTransport",
            targets: ["MacDisplayConnectTransport"]
        ),
        .executable(name: "MacDisplayConnect", targets: ["MacDisplayConnect"]),
    ],
    targets: [
        .target(
            name: "MacDisplayConnectCore",
            path: "Shared/Core/Sources"
        ),
        .target(
            name: "MacDisplayConnectTransport",
            dependencies: ["MacDisplayConnectCore"],
            path: "Shared/Transport/Sources"
        ),
        .executableTarget(
            name: "MacDisplayConnect",
            dependencies: [
                "MacDisplayConnectCore",
                "MacDisplayConnectTransport",
            ],
            path: "Apps/Mac/Sources"
        ),
        .testTarget(
            name: "MacDisplayConnectCoreTests",
            dependencies: ["MacDisplayConnectCore"],
            path: "Shared/Core/Tests"
        ),
        .testTarget(
            name: "MacDisplayConnectTransportTests",
            dependencies: [
                "MacDisplayConnectCore",
                "MacDisplayConnectTransport",
            ],
            path: "Shared/Transport/Tests"
        ),
        .testTarget(
            name: "MacDisplayConnectTests",
            dependencies: [
                "MacDisplayConnect",
                "MacDisplayConnectCore",
                "MacDisplayConnectTransport",
            ],
            path: "Apps/Mac/Tests"
        ),
    ]
)

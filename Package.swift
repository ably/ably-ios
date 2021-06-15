// swift-tools-version:5.4.0

import PackageDescription

let package = Package(
    name: "Ably",
    platforms: [
        .macOS(.v10_11),
        .iOS(.v9),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "Ably",
            targets: ["Ably"]
        ),
    ],
    dependencies: [
        .package(name: "msgpack", url: "https://github.com/rvi/msgpack-objective-C", from: "0.4.0"),
        .package(name: "AblyDeltaCodec", url: "https://github.com/ably/delta-codec-cocoa", .branch("main"))
    ],
    targets: [
        .target(
            name: "Ably",
            dependencies: [
                .byName(name: "msgpack"),
                .byName(name: "AblyDeltaCodec")
            ],
            path: ".",
            exclude: [
                "Info-tvOS.plist",
                "Info-macOS.plist",
                "Info-iOS.plist",
                "Ably-SoakTest-App",
                "Ably-SoakTest-AppUITests",
                "Spec",
                "Products",
                "Scripts",
                "fastlane",
                "Examples",
                "Carthage"
            ],
            sources: [
                "Source",
                "SocketRocket"
            ],
            publicHeadersPath: "Source/include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("Source"),
                .headerSearchPath("Source/Private"),
                .headerSearchPath("SocketRocket/SocketRocket"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/RunLoop"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/Security"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/Delegate"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/IOConsumer"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/Utilities"),
                .headerSearchPath("SocketRocket/SocketRocket/Internal/Proxy")
            ]
        )
    ]
)

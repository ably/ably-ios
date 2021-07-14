// swift-tools-version:5.3.0

import PackageDescription

let package = Package(
    name: "ably-cocoa",
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
            name: "SocketRocket",
            path: "SocketRocket/SocketRocket",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("Internal"),
                .headerSearchPath("Internal/Security"),
                .headerSearchPath("Internal/Proxy"),
                .headerSearchPath("Internal/Utilities"),
                .headerSearchPath("Internal/RunLoop"),
                .headerSearchPath("Internal/Delegate"),
                .headerSearchPath("Internal/IOConsumer")
            ]
        ),
        .target(
            name: "Ably",
            dependencies: [
                "SocketRocket",
                .byName(name: "msgpack"),
                .byName(name: "AblyDeltaCodec")
            ],
            path: "Source",
            exclude: [
                "Info-iOS.plist",
                "Info-tvOS.plist",
                "Info-macOS.plist"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("PrivateHeaders"),
                .headerSearchPath("PrivateHeaders/Ably"),
                .headerSearchPath("include/Ably")
            ]
        )
    ]
)


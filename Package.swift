// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nabiz",
            dependencies: ["NabizUnofficial"],
            path: "Sources/Nabiz",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Resmi olmayan / belgelenmemiş API'ler yalnızca bu hedefin yardımcılarıyla kullanılır (ADR 0003).
        .target(
            name: "NabizUnofficial",
            path: "Sources/NabizUnofficial",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NabizTests",
            dependencies: ["Nabiz", "NabizUnofficial"],
            path: "Tests/NabizTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

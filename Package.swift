// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VanessaNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vanessa-notch", targets: ["vanessa-notch"]),
    ],
    targets: [
        .target(name: "VanessaCore"),
        .target(name: "VanessaNetease", dependencies: ["VanessaCore"]),
        .target(name: "VanessaApp", dependencies: ["VanessaCore", "VanessaNetease"]),
        .executableTarget(name: "vanessa-notch", dependencies: ["VanessaApp"]),
        .testTarget(name: "VanessaCoreTests", dependencies: ["VanessaCore"]),
        .testTarget(name: "VanessaNeteaseTests", dependencies: ["VanessaNetease"]),
        .testTarget(name: "VanessaAppTests", dependencies: ["VanessaApp"]),
    ]
)

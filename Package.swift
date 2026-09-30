// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechWingman",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SpeechWingman", targets: ["WingmanApp"]),
        .executable(name: "wingman-evaluate", targets: ["WingmanEvaluate"])
    ],
    targets: [
        .target(name: "WingmanCore"),
        .executableTarget(name: "WingmanApp", dependencies: ["WingmanCore"]),
        .executableTarget(name: "WingmanEvaluate", dependencies: ["WingmanCore"]),
        .executableTarget(name: "WingmanCoreTests", dependencies: ["WingmanCore"], path: "Tests/WingmanCoreTests")
    ]
)

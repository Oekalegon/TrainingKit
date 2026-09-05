// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrainingKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TrainingCore", targets: ["TrainingCore"]),
        .library(name: "TrainingHealthKit", targets: ["TrainingHealthKit"]),
        .library(name: "TrainingWorkoutKit", targets: ["TrainingWorkoutKit"]),
        .library(name: "TrainingPersistence", targets: ["TrainingPersistence"]),
        .library(name: "TrainingTools", targets: ["TrainingTools"]),
        .library(name: "TrainingToolsAnthropic", targets: ["TrainingToolsAnthropic"]),
        .library(name: "TrainingToolsFoundationModels", targets: ["TrainingToolsFoundationModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(name: "TrainingCore"),
        .target(name: "TrainingHealthKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingWorkoutKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingPersistence", dependencies: ["TrainingCore"]),
        .target(name: "TrainingTools", dependencies: ["TrainingCore"]),
        .target(name: "TrainingToolsAnthropic", dependencies: ["TrainingTools"]),
        .target(name: "TrainingToolsFoundationModels", dependencies: ["TrainingTools"]),
        .testTarget(name: "TrainingCoreTests", dependencies: ["TrainingCore"]),
        .testTarget(name: "TrainingHealthKitTests", dependencies: ["TrainingHealthKit"]),
    ]
)

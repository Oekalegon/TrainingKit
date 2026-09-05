// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TrainingKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
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
    targets: [
        .target(name: "TrainingCore"),
        .target(name: "TrainingHealthKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingWorkoutKit", dependencies: ["TrainingCore"]),
        .target(name: "TrainingPersistence", dependencies: ["TrainingCore"]),
        .target(name: "TrainingTools", dependencies: ["TrainingCore"]),
        .target(name: "TrainingToolsAnthropic", dependencies: ["TrainingTools"]),
        .target(name: "TrainingToolsFoundationModels", dependencies: ["TrainingTools"]),
        .testTarget(name: "TrainingCoreTests", dependencies: ["TrainingCore"]),
    ]
)

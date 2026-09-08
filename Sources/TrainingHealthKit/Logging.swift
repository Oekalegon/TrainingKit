#if canImport(HealthKit)
import os

/// Shared `os.Logger` instances for `TrainingHealthKit`, mirroring `TrainingCore`'s own
/// `Logging.swift` — each target keeps its own since `TrainingCore.Logging` is `internal`.
enum Logging {
    private static let subsystem = "com.trainingKit"

    static let importer = Logger(subsystem: subsystem, category: "Import")
}
#endif

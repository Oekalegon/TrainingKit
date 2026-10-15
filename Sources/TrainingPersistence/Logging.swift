import os

/// Shared `os.Logger` instances for `TrainingPersistence`, in the same subsystem as `TrainingCore`'s.
enum Logging {
    static let persistence = Logger(subsystem: "com.trainingKit", category: "Persistence")
}

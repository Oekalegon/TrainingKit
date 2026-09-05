import os

/// Shared `os.Logger` instances for `TrainingCore`, per the categories in the design doc §3.3.
enum Logging {
    private static let subsystem = "com.trainingKit"

    static let dataImport = Logger(subsystem: subsystem, category: "Import")
    static let load = Logger(subsystem: subsystem, category: "Load")
    static let series = Logger(subsystem: subsystem, category: "Series")
    static let statistics = Logger(subsystem: subsystem, category: "Statistics")
    static let workoutKit = Logger(subsystem: subsystem, category: "WorkoutKit")
}

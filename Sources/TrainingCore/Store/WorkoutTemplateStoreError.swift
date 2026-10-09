/// Why a workout-template operation on ``TrainingModel`` failed.
public enum WorkoutTemplateStoreError: Error, Sendable, Equatable {
    /// The model's ``StoreSet`` has no ``WorkoutTemplateStore``.
    case notConfigured
}

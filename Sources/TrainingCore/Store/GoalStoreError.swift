/// Why a goal operation on ``TrainingModel`` failed.
public enum GoalStoreError: Error, Sendable, Equatable {
    /// The model's ``StoreSet`` has no ``GoalStore``.
    case notConfigured
}

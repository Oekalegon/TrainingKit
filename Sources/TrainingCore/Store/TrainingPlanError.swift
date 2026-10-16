import Foundation

/// Why a training-plan operation on ``TrainingModel`` failed.
public enum TrainingPlanError: Error, Sendable, Hashable {
    /// The ``StoreSet`` has no ``StoreSet/trainingPlanStore``.
    case notConfigured
    /// There is no plan with this id.
    case notFound(UUID)
    /// The plan has at least one planned workout that an activity completed, so it is history and is
    /// never deleted (archive it instead).
    case hasCompletedWorkouts(UUID)
    /// The planned workout was completed by an activity, so it and its link to that activity are
    /// history and are never deleted. Unlink the activity first if the match was wrong.
    case workoutIsCompleted(UUID)
}

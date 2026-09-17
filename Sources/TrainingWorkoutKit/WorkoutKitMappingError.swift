#if canImport(WorkoutKit)
import HealthKit
import WorkoutKit

/// Errors thrown while mapping between `TrainingCore`'s workout model and WorkoutKit's.
public enum WorkoutKitMappingError: Error, Sendable, Equatable {
    /// A `WorkoutGoal` case `StepGoal` has no equivalent for: `.energy` or
    /// `.poolSwimDistanceWithTime`.
    case unsupportedGoal(WorkoutGoal)
    /// `structuredWorkout(from:)` was given a `WorkoutPlan` that doesn't wrap a `CustomWorkout` —
    /// only that case round-trips to a `StructuredWorkout`.
    case unsupportedWorkoutKind(WorkoutPlan.Workout)
    /// This activity type isn't supported by `CustomWorkout` at all.
    case unsupportedActivity(HKWorkoutActivityType)
    /// A step's goal isn't supported by WorkoutKit for this activity, per
    /// `CustomWorkout.supportsGoal(_:activity:location:)`.
    case unsupportedGoalForActivity(WorkoutGoal, HKWorkoutActivityType)
    /// A step's alert isn't supported by WorkoutKit for this activity, per
    /// `CustomWorkout.supportsAlert(_:activity:location:)`. The alert itself isn't carried on the
    /// error — `any WorkoutAlert` isn't `Equatable` — but the activity it failed for is.
    case unsupportedAlertForActivity(HKWorkoutActivityType)
}
#endif

import TrainingCore

#if canImport(WorkoutKit)
import HealthKit
import WorkoutKit

/// The `CustomWorkout.supports*` checks `WorkoutKitBridge` validates every mapped step against,
/// factored out as data rather than called directly.
///
/// WorkoutKit's own support tables aren't publicly documented, so there's no reliable way to
/// exercise `WorkoutKitBridge`'s `unsupportedActivity`/`unsupportedGoalForActivity`/
/// `unsupportedAlertForActivity` throw paths in a test using the real `CustomWorkout` statics —
/// there's no known-stable "this combination is unsupported" fixture to assert against. This type
/// is the seam: tests substitute a fake that reports whatever they need as unsupported, while
/// production code always uses ``live``.
struct WorkoutKitSupportChecking: Sendable {
    var supportsActivity: @Sendable (HKWorkoutActivityType) -> Bool
    var supportsGoal: @Sendable (WorkoutGoal, HKWorkoutActivityType) -> Bool
    var supportsAlert: @Sendable (any WorkoutAlert, HKWorkoutActivityType) -> Bool

    /// Delegates to `CustomWorkout`'s real static support checks.
    static let live = WorkoutKitSupportChecking(
        supportsActivity: { CustomWorkout.supportsActivity($0) },
        supportsGoal: { CustomWorkout.supportsGoal($0, activity: $1) },
        supportsAlert: { CustomWorkout.supportsAlert($0, activity: $1) }
    )
}
#endif

#if canImport(WorkoutKit)
import WorkoutKit

/// Requests the authorization ``WorkoutKitBridge/schedule(_:workout:calendar:)`` needs to put
/// workouts on the Watch.
public enum WorkoutKitAuthorization {
    /// The current authorization state for scheduling workouts, without prompting.
    public static var state: WorkoutScheduler.AuthorizationState {
        get async {
            await WorkoutScheduler.shared.authorizationState
        }
    }

    /// Requests authorization to schedule workouts via `WorkoutScheduler`.
    @discardableResult
    public static func requestAuthorization() async -> WorkoutScheduler.AuthorizationState {
        await WorkoutScheduler.shared.requestAuthorization()
    }
}
#endif

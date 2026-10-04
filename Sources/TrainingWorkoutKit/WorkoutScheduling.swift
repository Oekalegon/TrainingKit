import Foundation

#if canImport(WorkoutKit)
import WorkoutKit

/// The `WorkoutScheduler` calls `WorkoutKitBridge` schedules through, factored out as data rather
/// than called directly.
///
/// `WorkoutScheduler` has no public initializer and `.shared` crashes outside an app bundle, so
/// `WorkoutKitBridge`'s scheduling logic (replacing an entry, keeping a completed one, removing
/// unknown ones) can't be exercised against the real thing in a test. This type is the seam: tests
/// substitute an in-memory fake, while production code always uses ``live``. Like
/// ``WorkoutKitSupportChecking``, it mirrors only the calls the bridge makes.
struct WorkoutScheduling: Sendable {
    /// One scheduled workout as the bridge sees it: WorkoutKit's `ScheduledWorkoutPlan`, copied
    /// into a type a test can build with any completion state.
    struct Entry: Sendable, Equatable {
        var plan: WorkoutPlan
        var date: DateComponents
        var complete: Bool
    }

    var scheduledWorkouts: @Sendable () async -> [Entry]
    var schedule: @Sendable (WorkoutPlan, DateComponents) async -> Void
    var remove: @Sendable (WorkoutPlan, DateComponents) async -> Void

    /// Delegates to `WorkoutScheduler.shared`, touching it only when a closure is called.
    static let live = WorkoutScheduling(
        scheduledWorkouts: {
            await WorkoutScheduler.shared.scheduledWorkouts.map {
                Entry(plan: $0.plan, date: $0.date, complete: $0.complete)
            }
        },
        schedule: { await WorkoutScheduler.shared.schedule($0, at: $1) },
        remove: { await WorkoutScheduler.shared.remove($0, at: $1) }
    )
}
#endif

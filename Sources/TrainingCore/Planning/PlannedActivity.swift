import Foundation

/// A planned future (or past-but-unreconciled) activity: a workout plus a date.
///
/// Everything else about a plan is derived, which is what lets MVP 2's plan generator emit plain
/// data rather than something bespoke.
public struct PlannedActivity: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this plan.
    public let id: UUID
    /// The library ``StructuredWorkout`` this plan schedules.
    public var workoutID: UUID
    /// Calendar day in the athlete's timezone.
    public var date: Date
    /// Manual override of ``TRIMPPlanEstimator``'s estimate.
    public var expectedLoadOverride: Double?
    /// Set by ``PlanReconciler`` once a completed activity is matched to this plan.
    public var completedActivityID: UUID?
    /// The micro-cycle this plan belongs to; derived from `date` when `nil`.
    public var cycleID: UUID?

    /// Creates a planned activity.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - workoutID: The library ``StructuredWorkout`` this plan schedules.
    ///   - date: Calendar day in the athlete's timezone.
    ///   - expectedLoadOverride: Manual override of the estimated load.
    ///   - completedActivityID: The matched ``Activity``'s id, if already reconciled.
    ///   - cycleID: The micro-cycle this plan belongs to; derived from `date` when `nil`.
    public init(
        id: UUID = UUID(),
        workoutID: UUID,
        date: Date,
        expectedLoadOverride: Double? = nil,
        completedActivityID: UUID? = nil,
        cycleID: UUID? = nil
    ) {
        self.id = id
        self.workoutID = workoutID
        self.date = date
        self.expectedLoadOverride = expectedLoadOverride
        self.completedActivityID = completedActivityID
        self.cycleID = cycleID
    }
}

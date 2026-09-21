import Foundation

/// The outcome of ``PlanReconciler/reconcile(activities:plans:workouts:athlete:)``.
public struct PlanReconciliation: Sendable {
    /// The activities, with `linkedPlanID` set on each one that was matched.
    public var activities: [Activity]
    /// The plans, with `completedActivityID` set on each one that was matched.
    public var plans: [PlannedActivity]
    /// Matches that were made but had a close runner-up, for the athlete to confirm or correct.
    public var ambiguities: [PlanMatchAmbiguity]

    /// Creates a reconciliation result.
    public init(activities: [Activity], plans: [PlannedActivity], ambiguities: [PlanMatchAmbiguity]) {
        self.activities = activities
        self.plans = plans
        self.ambiguities = ambiguities
    }
}

/// An automatic activity-to-plan match that another same-day, same-sport plan almost matched as
/// well — flagged rather than silently resolved.
public struct PlanMatchAmbiguity: Sendable, Hashable {
    /// The activity that was matched.
    public let activityID: UUID
    /// The plan it was linked to (the closest by duration).
    public let linkedPlanID: UUID
    /// The other plans whose duration was within ``PlanReconciler/ambiguityTolerance`` of the winner's.
    public let alternativePlanIDs: [UUID]

    /// Creates an ambiguity record.
    public init(activityID: UUID, linkedPlanID: UUID, alternativePlanIDs: [UUID]) {
        self.activityID = activityID
        self.linkedPlanID = linkedPlanID
        self.alternativePlanIDs = alternativePlanIDs
    }
}

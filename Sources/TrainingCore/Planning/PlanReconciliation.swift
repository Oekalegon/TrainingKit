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

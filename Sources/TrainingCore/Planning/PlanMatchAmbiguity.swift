import Foundation

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

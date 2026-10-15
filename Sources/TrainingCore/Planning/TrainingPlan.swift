import Foundation

/// A named training plan: the planned workouts and the cycle layout that belong together.
///
/// A plan owns nothing by itself. A ``PlannedActivity`` or ``TrainingCycle`` belongs to it through its
/// `planID`, which is what lets several plans exist side by side, only the ``PlanStatus/active`` one
/// feeding the fitness series and everything derived from it (MVP5-124). Stored in a
/// ``TrainingPlanStore``.
public struct TrainingPlan: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this plan.
    public let id: UUID
    /// A display name, e.g. "Marathon 2027" or "Current plan".
    public var name: String
    /// Whether the plan is a draft, in use or archived.
    public var status: PlanStatus
    /// The plan's macro cycle, once it has one.
    public var macroCycleID: UUID?
    /// The ``Race`` the plan builds towards, if any.
    public var targetRaceID: UUID?
    /// When the plan was created.
    public var createdDate: Date

    /// Creates a training plan.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: A display name.
    ///   - status: Whether the plan is a draft, in use or archived; defaults to ``PlanStatus/draft``.
    ///   - macroCycleID: The plan's macro cycle, if it has one yet.
    ///   - targetRaceID: The race the plan builds towards, if any.
    ///   - createdDate: When the plan was created; defaults to now.
    public init(
        id: UUID = UUID(),
        name: String,
        status: PlanStatus = .draft,
        macroCycleID: UUID? = nil,
        targetRaceID: UUID? = nil,
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.macroCycleID = macroCycleID
        self.targetRaceID = targetRaceID
        self.createdDate = createdDate
    }
}

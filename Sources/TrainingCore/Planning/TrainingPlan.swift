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
    /// The day the plan was cancelled; set while ``status`` is ``PlanStatus/cancelled``, `nil` otherwise.
    public var cancelledDate: Date?

    /// Creates a training plan.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: A display name.
    ///   - status: Whether the plan is a draft, in use or archived; defaults to ``PlanStatus/draft``.
    ///   - macroCycleID: The plan's macro cycle, if it has one yet.
    ///   - targetRaceID: The race the plan builds towards, if any.
    ///   - createdDate: When the plan was created; defaults to now.
    ///   - cancelledDate: The day the plan was cancelled, for a ``PlanStatus/cancelled`` plan.
    public init(
        id: UUID = UUID(),
        name: String,
        status: PlanStatus = .draft,
        macroCycleID: UUID? = nil,
        targetRaceID: UUID? = nil,
        createdDate: Date = .now,
        cancelledDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.macroCycleID = macroCycleID
        self.targetRaceID = targetRaceID
        self.createdDate = createdDate
        self.cancelledDate = cancelledDate
    }
}

extension TrainingPlan {
    /// The id of the plan that existing unassigned data is adopted into. Fixed, so two devices that
    /// each create it before iCloud has synced end up with one plan, not two.
    public static let currentPlanID = UUID(uuidString: "5C0DE000-0000-4000-8000-0000000000C1")!
}

extension Collection where Element == TrainingPlan {
    /// The plan in use. Normally the only active one; if a sync left several active (two devices
    /// each activated one), the oldest by `createdDate` (then id) is, so every device agrees.
    public var canonicalActivePlan: TrainingPlan? {
        filter { $0.status == .active }.min { ($0.createdDate, $0.id.uuidString) < ($1.createdDate, $1.id.uuidString) }
    }

    /// The ids of the plans that don't feed the series: every plan but the canonical active one.
    public var inactivePlanIDs: Set<UUID> {
        let active = canonicalActivePlan?.id
        return Set(filter { $0.id != active }.map(\.id))
    }
}

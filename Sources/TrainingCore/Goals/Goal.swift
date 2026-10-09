import Foundation

/// A non-event target the athlete is working towards, such as "sub-20 5k" or "run 1500 km this year".
///
/// Unlike a ``Race`` a goal has no date and no calendar presence: it never appears on a day, and
/// nothing in the calendar, the load series or ``PlanEvaluator`` reads it. It is model-only in
/// MVP 2; a management UI and plans that act on goals are MVP 5.
public struct Goal: Identifiable, Sendable, Codable, Hashable {
    /// A stable identifier for this goal.
    public let id: UUID
    /// The goal's display name, e.g. "Sub-20 5k".
    public var name: String
    /// What the goal asks for; see ``GoalTarget``.
    public var target: GoalTarget
    /// Anything the athlete wants to remember about the goal, such as why it matters or how to get there.
    public var notes: String?

    /// Creates a goal.
    ///
    /// - Parameters:
    ///   - id: A stable identifier; defaults to a new random `UUID`.
    ///   - name: The goal's display name.
    ///   - target: What the goal asks for.
    ///   - notes: Anything the athlete wants to remember about the goal.
    public init(id: UUID = UUID(), name: String, target: GoalTarget, notes: String? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.notes = notes
    }
}

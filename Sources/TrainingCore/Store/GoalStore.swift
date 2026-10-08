import Foundation

/// Storage contract for goals.
public protocol GoalStore: Sendable {
    /// Every goal, in no guaranteed order. Goals have no date, so there is no range to ask for.
    func goals() async throws -> [Goal]

    /// The goal with this id, if any.
    func goal(id: UUID) async throws -> Goal?

    /// Inserts new goals or replaces existing ones matched by `id`.
    func upsert(_ goals: [Goal]) async throws

    /// Removes the goal with this id, if any. A no-op if `id` doesn't exist.
    func deleteGoal(id: UUID) async throws
}

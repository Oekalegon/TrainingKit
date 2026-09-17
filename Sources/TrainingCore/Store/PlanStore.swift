import Foundation

/// Storage contract for planned activities.
public protocol PlanStore: Sendable {
    /// All plans whose `date` falls within `range`.
    func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity]

    /// Inserts new plans or replaces existing ones matched by `id`.
    func upsert(_ plans: [PlannedActivity]) async throws

    /// The plan with this id, if any.
    func plan(id: UUID) async throws -> PlannedActivity?

    /// Removes the plan with this id, if any. Unlike ``ActivityStore``, plans support deletion —
    /// they're user-editable, not imported records.
    func deletePlan(id: UUID) async throws
}

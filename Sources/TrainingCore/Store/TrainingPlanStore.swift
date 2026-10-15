import Foundation

/// Persistence for ``TrainingPlan`` values (MVP5-124).
///
/// Optional on ``StoreSet``: without one there are no plans in the sense of this protocol, and every
/// ``PlannedActivity`` and ``TrainingCycle`` counts, exactly as before plans existed.
public protocol TrainingPlanStore: Sendable {
    /// Every training plan, in no particular order.
    func trainingPlans() async throws -> [TrainingPlan]

    /// The plan with `id`, or `nil` if there is none.
    ///
    /// - Parameter id: The plan's id.
    func trainingPlan(id: UUID) async throws -> TrainingPlan?

    /// Inserts `plan`, or replaces the plan with the same id.
    ///
    /// Atomic: when `plan` is ``PlanStatus/active``, any other active plan becomes a
    /// ``PlanStatus/draft`` in the same write, so at most one plan is ever active.
    ///
    /// - Parameter plan: The plan to store.
    func upsertTrainingPlan(_ plan: TrainingPlan) async throws

    /// Removes the plan with `id` together with what belongs to it, in one write: its cycles and the
    /// planned workouts that no completed activity is linked to. A planned workout that was
    /// completed stays, with its `planID` now pointing at nothing, so the history behind the
    /// estimate refinement and the completed-workout list isn't lost. A no-op if there is no such plan.
    ///
    /// - Parameter id: The plan to remove.
    func deleteTrainingPlan(id: UUID) async throws
}

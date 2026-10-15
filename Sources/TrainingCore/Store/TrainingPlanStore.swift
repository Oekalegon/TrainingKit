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

    /// Removes the plan with `id` together with its cycles and its planned workouts, in one write.
    ///
    /// A plan with at least one planned workout that an activity completed is part of the athlete's
    /// history and is never deleted: nothing is changed and ``TrainingPlanError/hasCompletedWorkouts(_:)``
    /// is thrown. Archive such a plan instead (``PlanStatus/archived``). A no-op if there is no such plan.
    ///
    /// - Parameter id: The plan to remove.
    /// - Throws: ``TrainingPlanError/hasCompletedWorkouts(_:)`` as described, or whatever the store throws.
    func deleteTrainingPlan(id: UUID) async throws
}

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
    /// Atomic: when `plan` is ``PlanStatus/active``, any other active plan stops being active in the
    /// same write, so at most one plan is ever active. It becomes a ``PlanStatus/draft``, or, when
    /// `cancelingActivePlanOn` is given, a ``PlanStatus/cancelled`` plan with that
    /// ``TrainingPlan/cancelledDate``.
    ///
    /// - Parameters:
    ///   - plan: The plan to store.
    ///   - date: The day to cancel the previously active plan on instead of making it a draft, if any.
    func upsertTrainingPlan(_ plan: TrainingPlan, cancelingActivePlanOn date: Date?) async throws

    /// Moves everything that belongs to no plan into the active plan, in one write: planned workouts and
    /// cycles whose `planID` is `nil`. If no plan is active, `newPlan` (an active plan) is inserted first.
    /// Does nothing, and inserts nothing, when there is nothing to move.
    ///
    /// Done inside the store, as one fetch-and-save, so a link written to a planned workout at the same
    /// time (an import matching an activity) can't be overwritten by a stale copy.
    ///
    /// - Parameter newPlan: The plan to insert as the active one when none is.
    /// - Returns: `true` if anything was moved.
    func adoptUnassigned(intoActivePlanOrNew newPlan: TrainingPlan) async throws -> Bool

    /// Inserts `plan` together with its `cycles` and `plannedActivities`, in one write.
    ///
    /// Cycles are validated as for ``CycleStore/upsert(_:)``; if that, or anything else, fails, nothing
    /// is stored.
    ///
    /// - Parameters:
    ///   - plan: The plan to insert.
    ///   - cycles: Its cycles, with `planID` already set.
    ///   - plannedActivities: Its planned workouts, with `planID` already set.
    func insertTrainingPlan(_ plan: TrainingPlan, cycles: [TrainingCycle], plannedActivities: [PlannedActivity]) async throws

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

extension TrainingPlanStore {
    /// Stores `plan`; see ``upsertTrainingPlan(_:cancelingActivePlanOn:)``. Another active plan becomes a draft.
    ///
    /// - Parameter plan: The plan to store.
    public func upsertTrainingPlan(_ plan: TrainingPlan) async throws {
        try await upsertTrainingPlan(plan, cancelingActivePlanOn: nil)
    }
}

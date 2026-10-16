import Foundation

extension StoreSet {
    /// The ids of the plans that don't feed the fitness series: every plan that isn't the active one
    /// (drafts, archived and cancelled plans). Empty without a ``trainingPlanStore``.
    ///
    /// Read fresh from the store each time (a handful of rows), so a plan activated by another device
    /// through iCloud is seen at the next fetch.
    ///
    /// - Throws: Whatever the store throws.
    public func inactivePlanIDs() async throws -> Set<UUID> {
        guard let trainingPlanStore else { return [] }
        return try await trainingPlanStore.trainingPlans().inactivePlanIDs
    }

    /// The planned workouts in `range` that count: those of the active plan, plus any that belong to no
    /// plan (stored before plans existed), plus every one an activity completed, whatever its plan's
    /// status, so the history of a cancelled or archived plan stays in view. Everything, without a
    /// ``trainingPlanStore``.
    ///
    /// - Parameter range: The days to fetch, as for ``PlanStore/plans(in:)``.
    /// - Throws: Whatever the stores throw.
    public func activePlannedActivities(in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
        let inactive = try await inactivePlanIDs()
        let plans = try await planStore.plans(in: range)
        guard !inactive.isEmpty else { return plans }
        return plans.filter { $0.completedActivityID != nil || ($0.planID.map { !inactive.contains($0) } ?? true) }
    }

    /// The cycles overlapping `range` that count, chosen the way ``activePlannedActivities(in:)``
    /// chooses planned workouts.
    ///
    /// - Parameter range: The days to fetch, as for ``CycleStore/cycles(in:)``.
    /// - Throws: Whatever the stores throw.
    public func activeCycles(in range: ClosedRange<Date>) async throws -> [TrainingCycle] {
        let inactive = try await inactivePlanIDs()
        let cycles = try await cycleStore.cycles(in: range)
        guard !inactive.isEmpty else { return cycles }
        return cycles.filter { $0.planID.map { !inactive.contains($0) } ?? true }
    }
}

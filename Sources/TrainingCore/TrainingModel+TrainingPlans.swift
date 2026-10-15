import Foundation

/// Several training plans, one active at a time (MVP5-124).
///
/// Only the active plan's planned workouts and cycles are in ``TrainingModel/plans`` and
/// ``TrainingModel/cycles``, and so in the fitness series, statistics, activity matching and calendar
/// export. A draft or archived plan stays in the store, editable through the explicit-plan methods
/// below and previewable with ``plannedActivities(ofPlan:in:)``. Without a
/// ``StoreSet/trainingPlanStore`` none of this applies and everything counts, as before.
extension TrainingModel {
    /// The plan in use, or `nil` if none is active (or there is no ``StoreSet/trainingPlanStore``).
    public var activeTrainingPlan: TrainingPlan? {
        trainingPlans.first { $0.status == .active }
    }

    /// Creates a plan and stores it, making it the active plan if `status` is ``PlanStatus/active``
    /// (the previously active plan becomes a draft).
    ///
    /// - Parameters:
    ///   - name: The plan's display name.
    ///   - status: Defaults to ``PlanStatus/draft``.
    ///   - targetRaceID: The race the plan builds towards, if any.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Returns: The stored plan.
    /// - Throws: ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``, or
    ///   whatever the stores throw.
    @discardableResult
    public func createTrainingPlan(
        named name: String,
        status: PlanStatus = .draft,
        targetRaceID: UUID? = nil,
        asOf today: Date = .now
    ) async throws -> TrainingPlan {
        let plan = TrainingPlan(name: name, status: status, targetRaceID: targetRaceID)
        try await save(plan, asOf: today)
        return plan
    }

    /// Replaces the stored plan that has `plan`'s id (or inserts it), then reloads and recomputes.
    /// Activating a plan this way demotes the previously active one to a draft in the same write;
    /// archiving the active plan leaves none active, and the next workout added by hand starts a new
    /// "My plan".
    ///
    /// - Parameters:
    ///   - plan: The plan to store, e.g. a copy of an existing one with another name or status.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``, or
    ///   whatever the stores throw.
    public func save(_ plan: TrainingPlan, asOf today: Date = .now) async throws {
        try await requiredTrainingPlanStore().upsertTrainingPlan(plan)
        try await reloadPlanState(asOf: today)
    }

    /// Makes the plan with `id` the active one, demoting the previously active plan to a draft.
    ///
    /// - Parameters:
    ///   - id: The plan to activate.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notFound(_:)`` if there is no such plan, ``TrainingPlanError/notConfigured``
    ///   without a ``StoreSet/trainingPlanStore``, or whatever the stores throw.
    public func activateTrainingPlan(id: UUID, asOf today: Date = .now) async throws {
        try await setStatus(.active, ofTrainingPlan: id, asOf: today)
    }

    /// Sets the status of the plan with `id`; see ``save(_:asOf:)`` for what that does to the others.
    ///
    /// - Parameters:
    ///   - status: The new status.
    ///   - id: The plan to change.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notFound(_:)`` if there is no such plan, ``TrainingPlanError/notConfigured``
    ///   without a ``StoreSet/trainingPlanStore``, or whatever the stores throw.
    public func setStatus(_ status: PlanStatus, ofTrainingPlan id: UUID, asOf today: Date = .now) async throws {
        var plan = try await storedTrainingPlan(id)
        plan.status = status
        try await save(plan, asOf: today)
    }

    /// Renames the plan with `id`.
    ///
    /// - Parameters:
    ///   - name: The new display name.
    ///   - id: The plan to rename.
    /// - Throws: ``TrainingPlanError/notFound(_:)`` if there is no such plan, ``TrainingPlanError/notConfigured``
    ///   without a ``StoreSet/trainingPlanStore``, or whatever the stores throw.
    public func renameTrainingPlan(id: UUID, to name: String) async throws {
        var plan = try await storedTrainingPlan(id)
        plan.name = name
        try await requiredTrainingPlanStore().upsertTrainingPlan(plan)
        trainingPlans = try await requiredTrainingPlanStore().trainingPlans()
    }

    /// Copies the plan with `id` into a new draft: its cycles (with fresh ids, parents remapped) and
    /// the planned workouts from `today` on that no activity has completed, minus any completion link.
    ///
    /// - Parameters:
    ///   - id: The plan to copy.
    ///   - name: The copy's name; defaults to the original's name followed by " copy".
    ///   - today: Planned workouts before this day aren't copied.
    /// - Returns: The new draft.
    /// - Throws: ``TrainingPlanError/notFound(_:)`` if there is no such plan, ``TrainingPlanError/notConfigured``
    ///   without a ``StoreSet/trainingPlanStore``, or whatever the stores throw.
    @discardableResult
    public func duplicateTrainingPlan(id: UUID, named name: String? = nil, asOf today: Date = .now) async throws -> TrainingPlan {
        let original = try await storedTrainingPlan(id)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let from = calendar.startOfDay(for: today)

        let cycles = try await stores.cycleStore.cycles(in: Date.distantPast...Date.distantFuture).filter { $0.planID == id }
        var newCycleIDs: [UUID: UUID] = [:]
        for cycle in cycles { newCycleIDs[cycle.id] = UUID() }
        let copy = TrainingPlan(
            name: name ?? "\(original.name) copy",
            status: .draft,
            macroCycleID: original.macroCycleID.flatMap { newCycleIDs[$0] },
            targetRaceID: original.targetRaceID
        )
        let copiedCycles = cycles.map { cycle in
            TrainingCycle(
                id: newCycleIDs[cycle.id] ?? UUID(), level: cycle.level, phase: cycle.phase, loadRole: cycle.loadRole,
                name: cycle.name, dateRange: cycle.dateRange, parentID: cycle.parentID.flatMap { newCycleIDs[$0] },
                targetRaceID: cycle.targetRaceID, planID: copy.id
            )
        }
        let copiedPlans = try await stores.planStore.plans(in: from...Date.distantFuture)
            .filter { $0.planID == id && $0.completedActivityID == nil }
            .map { plan in
                PlannedActivity(
                    workoutID: plan.workoutID, date: plan.date, expectedLoadOverride: plan.expectedLoadOverride,
                    cycleID: plan.cycleID.flatMap { newCycleIDs[$0] }, planID: copy.id
                )
            }

        // The copy's row first, so a failure part-way leaves an empty draft rather than workouts and
        // cycles that belong to no plan.
        try await requiredTrainingPlanStore().upsertTrainingPlan(copy)
        if !copiedCycles.isEmpty { try await stores.cycleStore.upsert(copiedCycles) }
        if !copiedPlans.isEmpty { try await stores.planStore.upsert(copiedPlans) }
        try await reloadPlanState(asOf: today)
        return copy
    }

    /// Removes the plan with `id` with its cycles and its planned workouts that no activity has
    /// completed (see ``TrainingPlanStore/deleteTrainingPlan(id:)``), then reloads and recomputes.
    ///
    /// Nothing is removed from WorkoutKit from here, as for ``deletePlan(id:asOf:)``.
    ///
    /// - Parameters:
    ///   - id: The plan to remove.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``, or
    ///   whatever the stores throw.
    public func deleteTrainingPlan(id: UUID, asOf today: Date = .now) async throws {
        try await requiredTrainingPlanStore().deleteTrainingPlan(id: id)
        try await reloadPlanState(asOf: today)
    }

    /// The planned workouts of the plan with `id` in `range`, whether or not it is the active plan:
    /// what a preview of a draft shows. Read from the store, not from ``plans``.
    ///
    /// - Parameters:
    ///   - id: The plan.
    ///   - range: The days to fetch, as for ``PlanStore/plans(in:)``.
    /// - Throws: Whatever the store throws.
    public func plannedActivities(ofPlan id: UUID, in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
        try await stores.planStore.plans(in: range).filter { $0.planID == id }
    }

    /// The cycles of the plan with `id` overlapping `range`, whether or not it is the active plan.
    ///
    /// - Parameters:
    ///   - id: The plan.
    ///   - range: The days to fetch, as for ``CycleStore/cycles(in:)``.
    /// - Throws: Whatever the store throws.
    public func cycles(ofPlan id: UUID, in range: ClosedRange<Date>) async throws -> [TrainingCycle] {
        try await stores.cycleStore.cycles(in: range).filter { $0.planID == id }
    }

    // MARK: - Internals

    /// Stamps the active plan's id on every item without a plan, first creating "My plan" as the
    /// active plan if there is none. Items that already name a plan are left as they are. Returns
    /// `items` unchanged without a ``StoreSet/trainingPlanStore``.
    func assigningToActivePlan(_ items: [PlannedActivity]) async throws -> [PlannedActivity] {
        guard items.contains(where: { $0.planID == nil }), let planID = try await ensureActivePlanID() else { return items }
        return items.map { item in
            var item = item
            item.planID = item.planID ?? planID
            return item
        }
    }

    /// See ``assigningToActivePlan(_:)-(PlannedActivity)``; the same for cycles.
    func assigningToActivePlan(_ items: [TrainingCycle]) async throws -> [TrainingCycle] {
        guard items.contains(where: { $0.planID == nil }), let planID = try await ensureActivePlanID() else { return items }
        return items.map { item in
            var item = item
            item.planID = item.planID ?? planID
            return item
        }
    }

    /// The id of the active plan, creating a plan called "My plan" if there is none; `nil` without a
    /// ``StoreSet/trainingPlanStore``.
    func ensureActivePlanID() async throws -> UUID? {
        guard let store = stores.trainingPlanStore else { return nil }
        if let active = try await store.trainingPlans().first(where: { $0.status == .active }) {
            return active.id
        }
        let plan = TrainingPlan(name: "My plan", status: .active)
        try await store.upsertTrainingPlan(plan)
        trainingPlans = try await store.trainingPlans()
        return plan.id
    }

    /// Moves every planned workout and cycle that belongs to no plan (stored before plans existed, or
    /// written by another device or the sandbox without one) into the active plan, creating a plan
    /// called "Current plan" first if there is none. Best effort: a failure is logged and the load
    /// goes on, since an unassigned item counts anyway.
    func adoptUnassignedIntoActivePlan() async {
        guard let store = stores.trainingPlanStore else { return }
        do {
            let everything = Date.distantPast...Date.distantFuture
            let orphanPlans = try await stores.planStore.plans(in: everything).filter { $0.planID == nil }
            let orphanCycles = try await stores.cycleStore.cycles(in: everything).filter { $0.planID == nil }
            guard !orphanPlans.isEmpty || !orphanCycles.isEmpty else { return }

            let planID: UUID
            if let active = try await store.trainingPlans().first(where: { $0.status == .active }) {
                planID = active.id
            } else {
                let current = TrainingPlan(name: "Current plan", status: .active)
                try await store.upsertTrainingPlan(current)
                planID = current.id
            }
            // Cycles first: a plan's cycleID never needs the plan id, but a failure between the two
            // leaves workouts that still count (nil) rather than cycles that don't.
            try await stores.cycleStore.upsert(orphanCycles.map { cycle in
                TrainingCycle(
                    id: cycle.id, level: cycle.level, phase: cycle.phase, loadRole: cycle.loadRole, name: cycle.name,
                    dateRange: cycle.dateRange, parentID: cycle.parentID, targetRaceID: cycle.targetRaceID, planID: planID
                )
            })
            try await stores.planStore.upsert(orphanPlans.map { plan in
                var plan = plan
                plan.planID = planID
                return plan
            })
        } catch {
            Logging.load.error("Adopting unassigned plans failed: \(error.localizedDescription)")
        }
    }

    private func requiredTrainingPlanStore() throws -> any TrainingPlanStore {
        guard let store = stores.trainingPlanStore else { throw TrainingPlanError.notConfigured }
        return store
    }

    private func storedTrainingPlan(_ id: UUID) async throws -> TrainingPlan {
        guard let plan = try await requiredTrainingPlanStore().trainingPlan(id: id) else {
            throw TrainingPlanError.notFound(id)
        }
        return plan
    }

    /// Reloads the plan list, the active plan's planned workouts and cycles, and recomputes.
    private func reloadPlanState(asOf today: Date) async throws {
        trainingPlans = try await requiredTrainingPlanStore().trainingPlans()
        if let loadedRange {
            plans = try await stores.activePlannedActivities(in: loadedRange)
            cycles = try await stores.activeCycles(in: loadedRange)
        }
        await recompute(asOf: today)
    }
}

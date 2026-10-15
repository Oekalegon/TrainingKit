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
        trainingPlans.canonicalActivePlan
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
        let plan = TrainingPlan(name: name, status: status, targetRaceID: targetRaceID, createdDate: today)
        try await save(plan, asOf: today)
        return plan
    }

    /// Replaces the stored plan that has `plan`'s id (or inserts it), then reloads and recomputes.
    ///
    /// Activating a plan ends the previously active one in the same write. If that plan has a completed
    /// workout (the athlete has been following it), it is **cancelled** and dated today (its
    /// ``TrainingPlan/cancelledDate``), so starting a new plan mid-way leaves the old one behind as
    /// history; if it has none, it simply becomes a draft. Archiving or cancelling the active plan
    /// leaves none active, and the next workout added by hand starts a new "My plan".
    ///
    /// - Parameters:
    ///   - plan: The plan to store, e.g. a copy of an existing one with another name or status.
    ///   - today: The day a replaced plan is cancelled on, and passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``, or
    ///   whatever the stores throw.
    public func save(_ plan: TrainingPlan, asOf today: Date = .now) async throws {
        let store = try requiredTrainingPlanStore()
        var cancelDate: Date?
        if plan.status == .active,
           let current = try await store.trainingPlans().canonicalActivePlan, current.id != plan.id,
           try await trainingPlanHasCompletedWorkouts(id: current.id) {
            cancelDate = startOfDay(today)
        }
        try await store.upsertTrainingPlan(plan, cancelingActivePlanOn: cancelDate)
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
        plan.cancelledDate = status == .cancelled ? (plan.cancelledDate ?? startOfDay(today)) : nil
        try await save(plan, asOf: today)
    }

    /// Cancels the plan with `id` as of today: its status becomes ``PlanStatus/cancelled`` and its
    /// ``TrainingPlan/cancelledDate`` is set to the start of `today`. The plan, its cycles and every
    /// workout under it stay as history; the plan stops feeding the series (its completed workouts stay
    /// in ``plans``). Cancelling an already cancelled plan keeps its date.
    ///
    /// - Parameters:
    ///   - id: The plan to cancel.
    ///   - today: The day to cancel on, and passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notFound(_:)`` if there is no such plan, ``TrainingPlanError/notConfigured``
    ///   without a ``StoreSet/trainingPlanStore``, or whatever the stores throw.
    public func cancelTrainingPlan(id: UUID, asOf today: Date = .now) async throws {
        try await setStatus(.cancelled, ofTrainingPlan: id, asOf: today)
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
            targetRaceID: original.targetRaceID,
            createdDate: today
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

        try await requiredTrainingPlanStore().insertTrainingPlan(copy, cycles: copiedCycles, plannedActivities: copiedPlans)
        try await reloadPlanState(asOf: today)
        return copy
    }

    /// Removes the plan with `id` with its cycles and its planned workouts (see
    /// ``TrainingPlanStore/deleteTrainingPlan(id:)``), then reloads and recomputes. A plan with a
    /// completed workout is history and is refused; check with ``trainingPlanHasCompletedWorkouts(id:)``
    /// and offer to archive it instead.
    ///
    /// Nothing is removed from WorkoutKit from here, as for ``deletePlan(id:asOf:)``.
    ///
    /// - Parameters:
    ///   - id: The plan to remove.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``, or
    ///   ``TrainingPlanError/hasCompletedWorkouts(_:)`` for a plan with a completed workout, or whatever
    ///   the stores throw.
    public func deleteTrainingPlan(id: UUID, asOf today: Date = .now) async throws {
        try await requiredTrainingPlanStore().deleteTrainingPlan(id: id)
        try await reloadPlanState(asOf: today)
    }

    /// Whether an activity has completed at least one planned workout of the plan with `id`, which makes
    /// the plan history that ``deleteTrainingPlan(id:asOf:)`` refuses to remove. Read from the store,
    /// whatever the loaded range.
    ///
    /// - Parameter id: The plan.
    /// - Throws: Whatever the store throws.
    public func trainingPlanHasCompletedWorkouts(id: UUID) async throws -> Bool {
        try await stores.planStore.plans(in: Date.distantPast...Date.distantFuture)
            .contains { $0.planID == id && $0.completedActivityID != nil }
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
    func assigningToActivePlan(_ items: [PlannedActivity], asOf today: Date) async throws -> [PlannedActivity] {
        guard items.contains(where: { $0.planID == nil }), let planID = try await ensureActivePlanID(asOf: today) else { return items }
        return items.map { item in
            var item = item
            item.planID = item.planID ?? planID
            return item
        }
    }

    /// The same for cycles.
    func assigningToActivePlan(_ items: [TrainingCycle], asOf today: Date) async throws -> [TrainingCycle] {
        guard items.contains(where: { $0.planID == nil }), let planID = try await ensureActivePlanID(asOf: today) else { return items }
        return items.map { item in
            var item = item
            item.planID = item.planID ?? planID
            return item
        }
    }

    /// The id of the active plan, creating a plan called "My plan" if there is none; `nil` without a
    /// ``StoreSet/trainingPlanStore``.
    func ensureActivePlanID(asOf today: Date) async throws -> UUID? {
        guard let store = stores.trainingPlanStore else { return nil }
        if let active = try await store.trainingPlans().canonicalActivePlan {
            return active.id
        }
        let plan = TrainingPlan(name: "My plan", status: .active, createdDate: today)
        try await store.upsertTrainingPlan(plan)
        trainingPlans = try await store.trainingPlans()
        return plan.id
    }

    /// Moves every planned workout and cycle that belongs to no plan (stored before plans existed, or
    /// written by another device or the sandbox without one) into the active plan, creating the plan
    /// "Current plan" first if there is none. Done once per model, inside the store as one write
    /// (``TrainingPlanStore/adoptUnassigned(intoActivePlanOrNew:)``), so it can't overwrite a link an
    /// import writes at the same moment. Best effort: a failure is logged and the load goes on, since an
    /// unassigned item counts anyway, and it is tried again at the next load.
    func adoptUnassignedIntoActivePlan(asOf today: Date) async {
        guard !didAdoptUnassigned, let store = stores.trainingPlanStore else { return }
        do {
            let current = TrainingPlan(id: TrainingPlan.currentPlanID, name: "Current plan", status: .active, createdDate: today)
            _ = try await store.adoptUnassigned(intoActivePlanOrNew: current)
            didAdoptUnassigned = true
        } catch {
            Logging.load.error("Adopting unassigned plans failed: \(error.localizedDescription)")
        }
    }

    private func startOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        return calendar.startOfDay(for: date)
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

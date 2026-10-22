import Foundation

/// Previewing and committing a ``PlanProposal`` (MVP5-121).
extension TrainingModel {
    /// What committing `proposal` would replace, together with the proposal's own views.
    ///
    /// Reads the active plan's planned workouts from the store, whatever the loaded range, and changes
    /// nothing.
    ///
    /// - Parameters:
    ///   - proposal: The proposal to preview.
    ///   - today: The day the replaced workouts start on (start of day in the athlete's timezone).
    /// - Returns: The preview.
    /// - Throws: Whatever the stores throw.
    public func preview(_ proposal: PlanProposal, asOf today: Date = .now) async throws -> PlanPreview {
        guard let active = try await stores.trainingPlanStore?.trainingPlans().canonicalActivePlan else {
            return PlanPreview(proposal: proposal, replacedPlan: nil, replacedActivities: [], replacedPlanIsFollowed: false)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let upcoming = try await plannedActivities(ofPlan: active.id, in: calendar.startOfDay(for: today)...Date.distantFuture)
            .filter { $0.completedActivityID == nil }
            .sorted { $0.date < $1.date }
        return PlanPreview(
            proposal: proposal,
            replacedPlan: active,
            replacedActivities: upcoming,
            replacedPlanIsFollowed: try await trainingPlanHasCompletedWorkouts(id: active.id)
        )
    }

    /// Stores `proposal` as a new plan: its workouts in the library, then the plan with its cycles and
    /// planned workouts in one write, as a draft (see ``TrainingPlanStore/insertTrainingPlan(_:cycles:plannedActivities:)``);
    /// with `activate` the plan is then activated like ``save(_:asOf:)`` does (a followed plan is
    /// cancelled, otherwise the old plan becomes a draft; nothing is deleted).
    ///
    /// The plan gets **fresh ids** for its cycles and planned workouts (parents and cycle references
    /// remapped), so committing the same proposal twice makes two independent plans instead of moving
    /// the first plan's contents into the second. The proposal's workouts keep their ids: they are
    /// library entries, saved as they are, and a repeat commit finds them already there.
    ///
    /// The steps are separate writes: if the plan insert fails (for instance on overlapping cycles) the
    /// saved workouts stay in the library, and if activation fails the draft stays. A proposal with risks can always be saved as a draft; activating
    /// it needs `acceptingRisks`.
    ///
    /// - Parameters:
    ///   - proposal: The proposal to store.
    ///   - name: The plan's display name.
    ///   - activate: Whether to make the plan the active one; defaults to `false`.
    ///   - acceptingRisks: Whether activating a proposal with ``Severity/risk`` findings is allowed;
    ///     defaults to `false`.
    ///   - today: Passed through to activation and ``recompute(asOf:)``.
    /// - Returns: The stored plan (as it is after the commit, so active if `activate`).
    /// - Throws: ``PlanProposalError/hasRisks(_:)`` for activating without `acceptingRisks`;
    ///   ``PlanProposalError/missingWorkouts(_:)`` if planned workouts refer to workouts that are in
    ///   neither the proposal nor the library; ``PlanProposalError/workoutIDCollision(_:)`` if a
    ///   proposal workout would overwrite a different library workout;
    ///   ``PlanProposalError/danglingCycleReferences(_:)`` if a planned workout names a cycle the
    ///   proposal lacks; ``TrainingPlanError/notConfigured`` without a ``StoreSet/trainingPlanStore``;
    ///   or whatever the stores throw. Nothing is written when it throws one of the first five.
    @discardableResult
    public func commit(
        _ proposal: PlanProposal,
        named name: String,
        activate: Bool = false,
        acceptingRisks: Bool = false,
        asOf today: Date = .now
    ) async throws -> TrainingPlan {
        guard let store = stores.trainingPlanStore else { throw TrainingPlanError.notConfigured }
        if activate, !acceptingRisks, !proposal.isAcceptable { throw PlanProposalError.hasRisks(proposal.risks) }

        let library = Dictionary(
            try await stores.workoutStore.workouts().map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }
        )
        let proposed = Dictionary(proposal.candidate.workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let collisions = proposed.filter { library[$0.key] != nil && library[$0.key] != $0.value }.keys
        if !collisions.isEmpty { throw PlanProposalError.workoutIDCollision(collisions.sorted { $0.uuidString < $1.uuidString }) }
        let missing = Set(proposal.candidate.plannedActivities.map(\.workoutID)).subtracting(Set(library.keys).union(proposed.keys))
        if !missing.isEmpty { throw PlanProposalError.missingWorkouts(missing.sorted { $0.uuidString < $1.uuidString }) }
        let cycleIDs = Set(proposal.candidate.cycles.map(\.id))
        let dangling = Set(proposal.candidate.plannedActivities.compactMap(\.cycleID)).subtracting(cycleIDs)
        if !dangling.isEmpty { throw PlanProposalError.danglingCycleReferences(dangling.sorted { $0.uuidString < $1.uuidString }) }

        var draft = proposal.draftPlan(named: name)
        let stamped = proposal.stamped(with: draft)
        let newCycleIDs = Dictionary(uniqueKeysWithValues: stamped.cycles.map { ($0.id, UUID()) })
        let cycles = stamped.cycles.map { cycle in
            TrainingCycle(
                id: newCycleIDs[cycle.id] ?? UUID(), level: cycle.level, phase: cycle.phase, loadRole: cycle.loadRole,
                name: cycle.name, dateRange: cycle.dateRange, parentID: cycle.parentID.flatMap { newCycleIDs[$0] },
                targetRaceID: cycle.targetRaceID, planID: draft.id
            )
        }
        let activities = stamped.plannedActivities.map { activity in
            PlannedActivity(
                workoutID: activity.workoutID, date: activity.date, expectedLoadOverride: activity.expectedLoadOverride,
                cycleID: activity.cycleID.flatMap { newCycleIDs[$0] }, planID: draft.id
            )
        }
        draft.macroCycleID = draft.macroCycleID.flatMap { newCycleIDs[$0] }
        try await stores.workoutStore.upsert(proposal.candidate.workouts.filter { library[$0.id] == nil })
        try await store.insertTrainingPlan(draft, cycles: cycles, plannedActivities: activities)
        trainingPlans = try await store.trainingPlans()

        guard activate else { return draft }
        var active = draft
        active.status = .active
        try await save(active, asOf: today)
        return active
    }
}

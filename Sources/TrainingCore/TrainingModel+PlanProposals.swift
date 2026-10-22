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
    /// The steps are separate writes: if activation fails the draft stays, and the workouts saved
    /// before it stay in the library. A proposal with risks can always be saved as a draft; activating
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
    ///   neither the proposal nor the library; ``TrainingPlanError/notConfigured`` without a
    ///   ``StoreSet/trainingPlanStore``; or whatever the stores throw. Nothing is written when it throws
    ///   one of the first three.
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

        let known = Set(try await stores.workoutStore.workouts().map(\.id)).union(proposal.candidate.workouts.map(\.id))
        let missing = Set(proposal.candidate.plannedActivities.map(\.workoutID)).subtracting(known)
        if !missing.isEmpty { throw PlanProposalError.missingWorkouts(missing.sorted { $0.uuidString < $1.uuidString }) }

        let draft = proposal.draftPlan(named: name)
        let stamped = proposal.stamped(with: draft)
        try await stores.workoutStore.upsert(proposal.candidate.workouts)
        try await store.insertTrainingPlan(draft, cycles: stamped.cycles, plannedActivities: stamped.plannedActivities)
        trainingPlans = try await store.trainingPlans()

        guard activate else { return draft }
        var active = draft
        active.status = .active
        try await save(active, asOf: today)
        return active
    }
}

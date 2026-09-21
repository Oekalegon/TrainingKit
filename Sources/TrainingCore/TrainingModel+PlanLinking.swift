import Foundation

/// Linking completed activities to the plans they fulfilled: automatic matching via
/// ``PlanReconciler`` after an import, plus the manual link/unlink the Activity Detail sheet offers
/// when the automatic match is missing, wrong or flagged in ``planMatchAmbiguities``.
extension TrainingModel {
    /// Links the activity `activityID` to the plan `planID`, replacing whatever either was linked to.
    ///
    /// If the activity was linked to another plan, that plan becomes unmatched; likewise a different
    /// activity previously linked to `planID` becomes unlinked. Unlike the automatic match, a manual
    /// link isn't restricted to the same day or sport — the athlete knows best. Clears any
    /// ``planMatchAmbiguities`` entry for the activity, and reloads and recomputes.
    ///
    /// A no-op if either id isn't in the store.
    ///
    /// - Parameters:
    ///   - activityID: The completed activity.
    ///   - planID: The plan it fulfilled.
    ///   - today: Passed through to ``recompute(asOf:)``.
    public func linkActivity(id activityID: UUID, toPlan planID: UUID, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performLink(activityID: activityID, planID: planID, asOf: today) }
    }

    /// Removes the link between the activity `id` and its plan, if it has one.
    ///
    /// The activity isn't re-matched automatically afterwards (only newly imported activities are),
    /// so an unlink sticks. Clears any ``planMatchAmbiguities`` entry, and reloads and recomputes.
    ///
    /// - Parameters:
    ///   - id: The activity to unlink.
    ///   - today: Passed through to ``recompute(asOf:)``.
    public func unlinkActivity(id: UUID, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performUnlink(activityID: id, asOf: today) }
    }

    /// Automatically matches the loaded, still-unlinked ``activities`` to unmatched plans.
    ///
    /// Import already does this for the activities it adds; call this after adding plans for days
    /// that already have activities. Reads plans from the store, not ``plans``.
    ///
    /// - Parameter today: Passed through to ``recompute(asOf:)``.
    public func reconcilePlans(asOf today: Date = .now) async throws {
        try await runQueued {
            try await self.reconcile(self.activities.filter { $0.linkedPlanID == nil })
            try await self.reloadAfterLinkChange(from: self.activities.map(\.start).min(), asOf: today)
        }
    }

    /// Matches `candidates` against the store's plans on their days and persists the links.
    func reconcile(_ candidates: [Activity]) async throws {
        guard let earliest = candidates.map(\.start).min(), let latest = candidates.map(\.start).max() else { return }
        // A day either side, so the reconciler's timezone-aware same-day check has the plans it needs.
        let day: TimeInterval = 86_400
        let plans = try await stores.planStore.plans(in: earliest.addingTimeInterval(-day)...latest.addingTimeInterval(day))
        guard !plans.isEmpty else { return }
        let workouts = try await stores.workoutStore.workouts()

        let result = PlanReconciler().reconcile(activities: candidates, plans: plans, workouts: workouts, athlete: athlete)
        let linkedActivities = result.activities.filter { $0.linkedPlanID != nil }
        let linkedPlans = result.plans.filter { $0.completedActivityID != nil }
        guard !linkedActivities.isEmpty else { return }
        try await stores.activityStore.upsert(linkedActivities)
        try await stores.planStore.upsert(linkedPlans)
        let resolved = Set(result.ambiguities.map(\.activityID))
        planMatchAmbiguities.removeAll { resolved.contains($0.activityID) }
        planMatchAmbiguities.append(contentsOf: result.ambiguities)
    }

    private func performLink(activityID: UUID, planID: UUID, asOf today: Date) async throws {
        guard var activity = try await stores.activityStore.activity(id: activityID),
              var plan = try await stores.planStore.plan(id: planID) else { return }

        var activitiesToSave: [Activity] = []
        var plansToSave: [PlannedActivity] = []
        var earliest = min(activity.start, plan.date)

        if let oldPlanID = activity.linkedPlanID, oldPlanID != planID,
           var oldPlan = try await stores.planStore.plan(id: oldPlanID) {
            oldPlan.completedActivityID = nil
            plansToSave.append(oldPlan)
            earliest = min(earliest, oldPlan.date)
        }
        if let oldActivityID = plan.completedActivityID, oldActivityID != activityID,
           var oldActivity = try await stores.activityStore.activity(id: oldActivityID) {
            oldActivity.linkedPlanID = nil
            activitiesToSave.append(oldActivity)
            earliest = min(earliest, oldActivity.start)
        }

        activity.linkedPlanID = planID
        plan.completedActivityID = activityID
        activitiesToSave.append(activity)
        plansToSave.append(plan)

        try await stores.activityStore.upsert(activitiesToSave)
        try await stores.planStore.upsert(plansToSave)
        planMatchAmbiguities.removeAll { $0.activityID == activityID }
        try await reloadAfterLinkChange(from: earliest, asOf: today)
    }

    private func performUnlink(activityID: UUID, asOf today: Date) async throws {
        guard var activity = try await stores.activityStore.activity(id: activityID),
              let planID = activity.linkedPlanID else { return }
        var earliest = activity.start
        activity.linkedPlanID = nil
        try await stores.activityStore.upsert([activity])
        if var plan = try await stores.planStore.plan(id: planID), plan.completedActivityID == activityID {
            plan.completedActivityID = nil
            try await stores.planStore.upsert([plan])
            earliest = min(earliest, plan.date)
        }
        planMatchAmbiguities.removeAll { $0.activityID == activityID }
        try await reloadAfterLinkChange(from: earliest, asOf: today)
    }

    private func reloadAfterLinkChange(from day: Date?, asOf today: Date) async throws {
        if let day, let cache = stores.fitnessMetricsCacheStore {
            try? await cache.markDirty(from: day)
        }
        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        plans = try await stores.planStore.plans(in: range)
        await recompute(asOf: today)
    }
}

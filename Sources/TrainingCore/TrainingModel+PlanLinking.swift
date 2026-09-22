import Foundation

/// Linking completed activities to the plans they fulfilled: automatic matching via
/// ``PlanReconciler`` after an import, plus the manual link/unlink the Activity Detail sheet offers
/// when the automatic match is missing, wrong or flagged in ``planMatchAmbiguities``.
extension TrainingModel {
    /// Links the activity `activityID` to the plan `planID`, replacing whatever either was linked to.
    ///
    /// If the activity was linked to another plan, that plan becomes unmatched; likewise a different
    /// activity previously linked to `planID` becomes unlinked. Like the automatic match, a link must
    /// be within one calendar day (in the athlete's time zone); unlike it, the sport isn't checked —
    /// the athlete knows best. Clears any ``planMatchAmbiguities`` entry for the activity, and reloads
    /// and recomputes.
    ///
    /// A no-op if either id isn't in the store.
    ///
    /// - Throws: ``PlanLinkError/differentDay`` if the activity and the plan aren't on the same day
    ///   (nothing is changed), or whatever the stores throw.
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

    /// Automatically matches the loaded, still-unlinked ``activities`` to unmatched plans, first
    /// repairing any half-made link (see ``repairPlanLinks()``).
    ///
    /// Import already does this for the activities it adds; call this after adding plans for days
    /// that already have activities. Reads plans from the store, not ``plans``.
    ///
    /// - Parameter today: Passed through to ``recompute(asOf:)``.
    public func reconcilePlans(asOf today: Date = .now) async throws {
        try await runQueued {
            try await self.repairPlanLinks()
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

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        guard calendar.isDate(activity.start, inSameDayAs: plan.date) else { throw PlanLinkError.differentDay }

        var releasedActivities: [Activity] = []
        var releasedPlans: [PlannedActivity] = []
        var earliest = min(activity.start, plan.date)

        if let oldPlanID = activity.linkedPlanID, oldPlanID != planID,
           var oldPlan = try await stores.planStore.plan(id: oldPlanID) {
            oldPlan.completedActivityID = nil
            releasedPlans.append(oldPlan)
            earliest = min(earliest, oldPlan.date)
        }
        if let oldActivityID = plan.completedActivityID, oldActivityID != activityID,
           var oldActivity = try await stores.activityStore.activity(id: oldActivityID) {
            oldActivity.linkedPlanID = nil
            releasedActivities.append(oldActivity)
            earliest = min(earliest, oldActivity.start)
        }

        activity.linkedPlanID = planID
        plan.completedActivityID = activityID

        // Activities and plans live in two stores that can't commit together, so the order limits
        // what a failure can leave behind: everything being released is written first, the new
        // link's two halves last. A throw before them leaves things unlinked, never double-linked;
        // a throw between the last two leaves a half link that ``repairPlanLinks()`` completes.
        try await stores.activityStore.upsert(releasedActivities)
        try await stores.planStore.upsert(releasedPlans)
        try await stores.activityStore.upsert([activity])
        try await stores.planStore.upsert([plan])
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
        try await reloadActivitiesAndPlans(in: range, bestEffortPlans: false)
        await recompute(asOf: today)
    }

    /// Frees the plans held by the activities `ids` (each one whose ``PlannedActivity/completedActivityID``
    /// is that activity), for when those activities are about to be removed — otherwise the plan would
    /// stay "completed" by an activity that no longer exists and could never be matched again. Call
    /// *before* removing them, since it reads their links from the store.
    func releasePlans(heldBy ids: [UUID]) async throws {
        for id in ids {
            guard let activity = try await stores.activityStore.activity(id: id),
                  let planID = activity.linkedPlanID,
                  var plan = try await stores.planStore.plan(id: planID),
                  plan.completedActivityID == id else { continue }
            plan.completedActivityID = nil
            try await stores.planStore.upsert([plan])
        }
        planMatchAmbiguities.removeAll { ids.contains($0.activityID) }
        if let loadedRange { plans = try await stores.planStore.plans(in: loadedRange) }
    }

    /// Frees the activity linked to the plan `planID`, for when the plan is about to be deleted —
    /// otherwise the activity would keep a dead ``Activity/linkedPlanID`` and never be matched again.
    func releaseActivity(heldBy planID: UUID) async throws {
        if let plan = try await stores.planStore.plan(id: planID),
           let activityID = plan.completedActivityID,
           var activity = try await stores.activityStore.activity(id: activityID),
           activity.linkedPlanID == planID {
            activity.linkedPlanID = nil
            try await stores.activityStore.upsert([activity])
            if let loadedRange { activities = try await stores.activityStore.activities(in: loadedRange) }
        }
        planMatchAmbiguities.removeAll { $0.linkedPlanID == planID }
    }

    /// Repoints the plans held by `oldOwnerIDs` (pieces or joins that `merged` replaces) at `merged`.
    /// A plan `merged` doesn't carry is freed instead: a join has only one ``Activity/linkedPlanID``.
    func handOverPlans(from oldOwnerIDs: [UUID], planIDs: [UUID], to merged: Activity) async throws {
        for planID in Set(planIDs) {
            guard var plan = try await stores.planStore.plan(id: planID),
                  let holder = plan.completedActivityID, oldOwnerIDs.contains(holder) else { continue }
            plan.completedActivityID = merged.linkedPlanID == planID ? merged.id : nil
            try await stores.planStore.upsert([plan])
        }
        planMatchAmbiguities.removeAll { oldOwnerIDs.contains($0.activityID) }
    }

    /// Makes the two halves of every loaded link agree again.
    ///
    /// A link is stored on both sides (``Activity/linkedPlanID`` and ``PlannedActivity/completedActivityID``)
    /// in two stores that can't commit together, so a failure partway through a change can leave one
    /// side set. For each loaded activity that names a plan: a missing plan drops the link; a plan
    /// that's free (or held by one of the activity's own pieces) is pointed back at the activity; a
    /// plan held by something else drops the activity's link. Then any loaded plan whose holder is
    /// gone, or doesn't name the plan back, is freed.
    func repairPlanLinks() async throws {
        for activity in activities {
            guard let planID = activity.linkedPlanID else { continue }
            guard var plan = try await stores.planStore.plan(id: planID) else {
                var cleared = activity
                cleared.linkedPlanID = nil
                try await stores.activityStore.upsert([cleared])
                continue
            }
            if plan.completedActivityID == activity.id { continue }
            let pieces = try await stores.activityStore.components(ofJoinedActivity: activity.id).map(\.id)
            if plan.completedActivityID == nil || plan.completedActivityID.map(pieces.contains) == true {
                plan.completedActivityID = activity.id
                try await stores.planStore.upsert([plan])
            } else {
                var cleared = activity
                cleared.linkedPlanID = nil
                try await stores.activityStore.upsert([cleared])
            }
        }
        for var plan in try await loadedPlansFromStore() {
            guard let holderID = plan.completedActivityID else { continue }
            let holder = try await stores.activityStore.activity(id: holderID)
            if holder?.linkedPlanID != plan.id {
                plan.completedActivityID = nil
                try await stores.planStore.upsert([plan])
            }
        }
        if let loadedRange {
            activities = try await stores.activityStore.activities(in: loadedRange)
            plans = try await stores.planStore.plans(in: loadedRange)
        }
    }

    private func loadedPlansFromStore() async throws -> [PlannedActivity] {
        guard let loadedRange else { return [] }
        return try await stores.planStore.plans(in: loadedRange)
    }
}

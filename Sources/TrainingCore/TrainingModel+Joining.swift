import Foundation

/// `joinActivities(_:_:asOf:)`, `unjoinActivity(id:asOf:)` and `components(ofJoinedActivity:)`, the
/// resolution actions for an ``OverlapRecommendation/join`` pair — split into its own file for the
/// same reason `TrainingModel+OverlapResolution.swift` is.
extension TrainingModel {
    /// Joins the activities `firstID` and `secondID` — pieces of one session that was accidentally
    /// recorded in two — into a single activity (see ``Activity/joined(_:_:)``).
    ///
    /// Nothing is deleted: the originals stay in the store, still tied to their own `source`, and
    /// ``ActivityStore/activities(in:)`` shows the joined activity in their place. That keeps a
    /// re-import from resurrecting them as separate activities, lets HealthKit corrections to a
    /// piece keep landing on it, and makes the join reversible via ``unjoinActivity(id:asOf:)``.
    ///
    /// Either id may itself be a joined activity, in which case its components are flattened into
    /// the new join and the old joined activity is replaced — joining a third piece onto an
    /// already-joined pair yields one join of three, not a join of a join.
    ///
    /// Invalidates the fitness-metrics cache from the earliest piece's day, reloads `activities`,
    /// and recomputes. Serialized through the same ``pendingImport`` queue as
    /// import/deduplication/deletion.
    ///
    /// A no-op if either id isn't in the store or both ids are the same.
    ///
    /// The joined activity is a snapshot of its pieces, rebuilt by ``importActivities(from:asOf:)``
    /// whenever a re-import changes one of them (keeping the join's own plan link and perceived
    /// exertion if it has them), so HealthKit corrections to a piece still reach it.
    ///
    /// - Throws: ``ActivityJoinError/differentSportFamilies`` if the pieces aren't all one sport
    ///   family, or ``ActivityJoinError/componentAlreadyJoined(_:)`` if one already belongs to a
    ///   join that isn't being flattened into this one (both leave the store unchanged). Also
    ///   whatever the ``ActivityStore`` throws saving the join or reloading afterwards: the join
    ///   itself is saved atomically, but if only the reload fails the join is committed while
    ///   ``activities`` stays stale until the next ``load(in:asOf:)``.
    ///
    /// - Parameters:
    ///   - firstID: One piece (or joined activity).
    ///   - secondID: The other piece (or joined activity).
    ///   - today: Passed through to ``recompute(asOf:)``.
    public func joinActivities(_ firstID: UUID, _ secondID: UUID, asOf today: Date = .now) async throws {
        guard firstID != secondID else { return }
        try await runQueued { try await self.performJoin(firstID, secondID, asOf: today) }
    }

    /// Splits the joined activity `id` back into its original pieces.
    ///
    /// A no-op if `id` isn't a joined activity. Serialized and recomputed like
    /// ``joinActivities(_:_:asOf:)``.
    ///
    /// - Parameters:
    ///   - id: The joined activity to undo.
    ///   - today: Passed through to ``recompute(asOf:)``.
    public func unjoinActivity(id: UUID, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performUnjoin(id: id, asOf: today) }
    }

    /// The pieces the joined activity `id` was built from, earliest first — what a detail view
    /// lists under "Joined from" — or an empty array if `id` isn't a joined activity.
    public func components(ofJoinedActivity id: UUID) async throws -> [Activity] {
        try await stores.activityStore.components(ofJoinedActivity: id)
    }

    private func performJoin(_ firstID: UUID, _ secondID: UUID, asOf today: Date) async throws {
        // From the store, not `self.activities`, for the same reason as `performDeleteActivity`.
        guard let first = try await stores.activityStore.activity(id: firstID),
              let second = try await stores.activityStore.activity(id: secondID) else { return }

        var pieces: [Activity] = []
        var replacedJoinIDs: [UUID] = []
        for activity in [first, second] {
            let components = try await stores.activityStore.components(ofJoinedActivity: activity.id)
            if components.isEmpty {
                pieces.append(activity)
            } else {
                pieces.append(contentsOf: components)
                replacedJoinIDs.append(activity.id)
            }
        }
        pieces.sort { $0.start < $1.start }
        guard let earliest = pieces.first, pieces.count >= 2 else { return }

        guard pieces.allSatisfy({ $0.sport.isSameFamily(as: earliest.sport) }) else {
            throw ActivityJoinError.differentSportFamilies
        }
        guard let merged = Activity.joined(pieces) else { return }
        try await stores.activityStore.saveJoin(merged, components: pieces.map(\.id), replacing: replacedJoinIDs)

        try await reloadAfterJoinChange(from: earliest.start, asOf: today)
    }

    private func performUnjoin(id: UUID, asOf today: Date) async throws {
        guard let joined = try await stores.activityStore.activity(id: id) else { return }
        try await stores.activityStore.unjoinActivity(id: id)
        try await reloadAfterJoinChange(from: joined.start, asOf: today)
    }

    private func reloadAfterJoinChange(from day: Date, asOf today: Date) async throws {
        if let cache = stores.fitnessMetricsCacheStore {
            try? await cache.markDirty(from: day)
        }
        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        await recompute(asOf: today)
    }

    /// Rebuilds every joined activity that any of `pieceIDs` belongs to from its (possibly just
    /// re-imported) pieces, in place under the same id, and returns the days that need their
    /// fitness-metrics cache invalidated (the earlier of the old and rebuilt start).
    ///
    /// The join's own ``Activity/linkedPlanID`` and ``Activity/perceivedExertion`` survive the
    /// rebuild when set — the reconciler or the athlete may have set them on the joined activity
    /// itself — so a later change to a piece's own exertion doesn't override them.
    func refreshJoins(containing pieceIDs: [UUID]) async throws -> [Date] {
        var refreshed: Set<UUID> = []
        var days: [Date] = []
        for pieceID in pieceIDs {
            guard let existing = try await stores.activityStore.joinedActivity(containing: pieceID),
                  refreshed.insert(existing.id).inserted else { continue }
            let components = try await stores.activityStore.components(ofJoinedActivity: existing.id)
            guard var rebuilt = Activity.joined(components, id: existing.id) else { continue }
            rebuilt.linkedPlanID = existing.linkedPlanID ?? rebuilt.linkedPlanID
            rebuilt.perceivedExertion = existing.perceivedExertion ?? rebuilt.perceivedExertion
            try await stores.activityStore.saveJoin(rebuilt, components: components.map(\.id), replacing: [])
            days.append(min(existing.start, rebuilt.start))
        }
        return days
    }
}

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
    /// - Throws: Whatever the ``ActivityStore`` throws saving the join or reloading afterwards; the
    ///   join itself is saved atomically, so a failure there leaves the store unchanged.
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

        let merged = pieces.dropFirst().reduce(earliest) { Activity.joined($0, $1) }
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
}

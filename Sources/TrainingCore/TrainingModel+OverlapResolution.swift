import Foundation

/// `deleteActivity(id:)`, the resolution action for one side of an ``ActivityOverlapChecker``
/// pair (MVP1-63) — split into its own file for the same reason
/// `TrainingModel+Deduplication.swift` is: it only touches ``ActivityStore``, no
/// `ActivityImporting`/`TrainingHealthKit` dependency.
extension TrainingModel {
    /// Removes the activity with id `id` — the app's action for resolving an
    /// ``ActivityOverlapChecker`` pair once the athlete has picked which one to keep
    /// (``OverlapRecommendation/duplicate(keep:remove:)``'s `remove`, or whichever side of a
    /// ``OverlapRecommendation/merge``/``OverlapRecommendation/conflict`` pair they didn't keep).
    ///
    /// Invalidates the fitness-metrics cache from `id`'s own day forward, reloads `activities`,
    /// and recomputes — same shape as ``deduplicateActivities(asOf:)``. A no-op if `id` doesn't
    /// exist in the store at all (already removed, or never existed); unlike `activities` itself,
    /// this isn't limited to whatever ``loadedRange`` currently covers — an activity that exists
    /// in the store but isn't currently loaded is still removed.
    ///
    /// Serialized against any in-flight import/deduplication via the same ``pendingImport`` queue
    /// those use, for the same reason those serialize against each other.
    ///
    /// - Parameters:
    ///   - id: The activity to remove.
    ///   - today: Passed through to ``recompute(asOf:)``.
    public func deleteActivity(id: UUID, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performDeleteActivity(id: id, asOf: today) }
    }

    private func performDeleteActivity(id: UUID, asOf today: Date) async throws {
        // Looked up from the store, not `self.activities`: the same reasoning as
        // `TrainingModel+Import.swift`'s `performImport` capturing a deleted source's date before
        // deleting it — once it's gone, only the store (not the in-memory, `loadedRange`-scoped
        // `activities`) can reliably answer whether/when it existed.
        guard let removedDay = try await stores.activityStore.activity(id: id)?.start else { return }
        // Everything that goes with it: a joined activity's pieces, or the join a piece belongs to.
        var removedIDs = [id]
        removedIDs += try await stores.activityStore.components(ofJoinedActivity: id).map(\.id)
        if let join = try await stores.activityStore.joinedActivity(containing: id) { removedIDs.append(join.id) }
        try await releasePlans(heldBy: removedIDs)
        try await stores.activityStore.deleteActivity(id: id)

        if let cache = stores.fitnessMetricsCacheStore {
            try? await cache.markDirty(from: removedDay)
        }

        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        await recompute(asOf: today)
    }
}

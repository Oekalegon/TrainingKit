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
    /// and recomputes — same shape as ``deduplicateActivities(asOf:)``. A no-op if `id` isn't
    /// currently loaded in `activities` (already removed, or outside ``loadedRange``).
    ///
    /// Serialized against any in-flight import/deduplication via the same ``pendingImport`` queue
    /// those use, for the same reason those serialize against each other.
    ///
    /// - Parameter today: Passed through to ``recompute(asOf:)``.
    public func deleteActivity(id: UUID, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performDeleteActivity(id: id, asOf: today) }
    }

    private func performDeleteActivity(id: UUID, asOf today: Date) async throws {
        guard let removedDay = activities.first(where: { $0.id == id })?.start else { return }
        try await stores.activityStore.deleteActivity(id: id)

        if let cache = stores.fitnessMetricsCacheStore {
            try? await cache.markDirty(from: removedDay)
        }

        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        await recompute(asOf: today)
    }
}

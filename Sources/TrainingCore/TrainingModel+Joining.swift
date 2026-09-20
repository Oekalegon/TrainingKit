import Foundation

/// `mergeActivities(_:_:asOf:)`, the resolution action for an ``OverlapRecommendation/join`` pair
/// — split into its own file for the same reason `TrainingModel+OverlapResolution.swift` is.
extension TrainingModel {
    /// Replaces the two activities `firstID` and `secondID` with one combined activity (see
    /// ``Activity/joined(_:_:)``).
    ///
    /// The merged activity is stored first, then both originals are removed via
    /// ``ActivityStore/deleteActivity(id:)`` so their sources are tombstoned and a later re-import
    /// won't bring the pieces back. Invalidates the fitness-metrics cache from the earlier
    /// piece's day, reloads `activities`, and recomputes. Serialized through the same
    /// ``pendingImport`` queue as import/deduplication/deletion.
    ///
    /// - Parameters:
    ///   - firstID: One piece.
    ///   - secondID: The other piece.
    ///   - today: Passed through to ``recompute(asOf:)``.
    ///
    /// A no-op if either id isn't in the store or both ids are the same.
    public func mergeActivities(_ firstID: UUID, _ secondID: UUID, asOf today: Date = .now) async throws {
        guard firstID != secondID else { return }
        try await runQueued { try await self.performMerge(firstID, secondID, asOf: today) }
    }

    private func performMerge(_ firstID: UUID, _ secondID: UUID, asOf today: Date) async throws {
        // From the store, not `self.activities`, for the same reason as `performDeleteActivity`.
        guard let a = try await stores.activityStore.activity(id: firstID),
              let b = try await stores.activityStore.activity(id: secondID) else { return }

        let merged = Activity.joined(a, b)
        try await stores.activityStore.upsert([merged])
        try await stores.activityStore.deleteActivity(id: a.id)
        try await stores.activityStore.deleteActivity(id: b.id)

        if let cache = stores.fitnessMetricsCacheStore {
            try? await cache.markDirty(from: merged.start)
        }

        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        await recompute(asOf: today)
    }
}

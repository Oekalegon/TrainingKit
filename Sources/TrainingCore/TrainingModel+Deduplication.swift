import Foundation

/// `deduplicateActivities(asOf:)`, split into its own file since — unlike
/// `TrainingModel+Import.swift` — it has no `ActivityImporting`/`TrainingHealthKit` dependency; it
/// only touches ``ActivityStore``.
extension TrainingModel {
    /// Removes duplicate `Activity` records already sitting in the store (see
    /// ``ActivityStore/deduplicateActivities()``), invalidates the fitness-metrics cache from the
    /// earliest affected day, reloads `activities`, and recomputes.
    ///
    /// A one-time cleanup for duplicates persisted before `ActivityStore.upsert(_:)`'s
    /// defense-in-depth dedup existed — that dedup only clears a stale duplicate when a *new*
    /// activity for the same source arrives, so it never retroactively fixes rows already in the
    /// store from before it shipped. Also worth running after restoring a store, such as a device
    /// backup, that predates the dedup fix.
    ///
    /// Serialized against any in-flight ``importActivities(from:asOf:)``/
    /// ``resyncActivities(from:asOf:)`` via the same ``pendingImport`` queue those use, so a
    /// concurrent import can't upsert a "duplicate" back in right after this removes it, or vice
    /// versa.
    ///
    /// - Parameter today: Passed through to ``recompute(asOf:)``.
    public func deduplicateActivities(asOf today: Date = .now) async throws {
        try await runQueued { try await self.performDeduplication(asOf: today) }
    }

    private func performDeduplication(asOf today: Date) async throws {
        let removed = try await stores.activityStore.deduplicateActivities()
        guard let earliest = removed.map(\.start).min() else { return }

        await markCacheDirty(from: earliest)

        let range = loadedRange ?? (today...today)
        activities = try await stores.activityStore.activities(in: range)
        await recompute(asOf: today)
    }
}

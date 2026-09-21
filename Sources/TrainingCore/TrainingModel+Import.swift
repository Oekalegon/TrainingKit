import Foundation

/// `importActivities(from:)`, split into its own file per the design's note that
/// `TrainingHealthKit`-dependent facade methods would arrive as additive extensions.
extension TrainingModel {
    /// Runs an incremental import via `importer`, persists the results, and recomputes.
    ///
    /// Reads the previously persisted anchor from ``AthleteStore/importAnchor()``, passes it to
    /// `importer.importActivities(since:)`, then upserts/deletes what came back and saves the new
    /// anchor — the same anchor-cursor round trip every ``ActivityImporting`` conformer expects,
    /// so callers (e.g. the app on pull-to-refresh) never touch `ImportAnchor` themselves.
    ///
    /// - Parameters:
    ///   - importer: The external source to import from, e.g. `HealthKitActivityImporter`.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: Whatever `importer` or the stores throw. Errors surface after whatever already
    ///   completed (e.g. the upsert) has been persisted — only the anchor save and reload are
    ///   skipped, so a failed anchor save simply makes the next import re-fetch what this one
    ///   already wrote, which `upsert`'s id-matched replace makes harmless.
    ///
    /// Serialized against any other in-flight ``importActivities(from:asOf:)``/
    /// ``resyncActivities(from:asOf:)`` call via ``pendingImport``: this run waits for whatever's
    /// already queued to finish before doing its own anchor-read-then-upsert. Without this, two
    /// overlapping calls (e.g. HealthKit background delivery firing during a manual pull-to-refresh,
    /// or a resync racing a normal import) can both read the same stale anchor, both ask the
    /// importer for activities the store doesn't have yet, and both end up inserting the same
    /// HealthKit workout under a different `Activity.id` — `ActivityStore.upsert` matches by id, not
    /// source, so neither insert looks like a duplicate to it. Queueing closes that window by making
    /// sure only one call is ever between the anchor read and the anchor save at a time.
    public func importActivities(from importer: any ActivityImporting, asOf today: Date = .now) async throws {
        try await runQueued { try await self.performImport(from: importer, asOf: today) }
    }

    /// Clears the persisted import anchor, then runs ``importActivities(from:asOf:)``.
    ///
    /// A cleared anchor makes `importer.importActivities(since:)` treat the run as a full import —
    /// e.g. `HealthKitActivityImporter` passes `nil` to `HKAnchoredObjectQueryDescriptor`, which
    /// redelivers every matching HealthKit sample rather than only what changed since some prior
    /// point. `ActivityStore.upsert(_:)` still matches by id, so re-delivered activities replace
    /// their existing records in place rather than duplicating them.
    ///
    /// Use this to pick up a mapping change (e.g. a `Sport` case that used to fall back to
    /// `.other`) for activities that were already imported before the fix, since `Sport` is
    /// resolved once at import time and persisted, not recomputed on every read.
    ///
    /// - Parameters:
    ///   - importer: The external source to import from, e.g. `HealthKitActivityImporter`.
    ///   - today: Passed through to ``recompute(asOf:)``.
    /// - Throws: Whatever `importActivities(from:asOf:)` throws, or whatever
    ///   ``AthleteStore/saveImportAnchor(_:)`` throws clearing the anchor beforehand. In either
    ///   case the anchor stays cleared — the next import (resync or otherwise) will also be a full
    ///   one, which `upsert`'s id-matched replace makes harmless, same as a failed anchor save in
    ///   ``importActivities(from:asOf:)`` itself.
    ///
    /// The anchor clear is queued behind any in-flight import too (not run immediately), for the
    /// same reason ``importActivities(from:asOf:)`` queues: an import already in flight would
    /// otherwise save its own (pre-resync) anchor right after this clears it, silently undoing the
    /// resync and leaving the next run incremental instead of full.
    public func resyncActivities(from importer: any ActivityImporting, asOf today: Date = .now) async throws {
        try await runQueued {
            try await self.stores.athleteStore.saveImportAnchor(nil)
            try await self.performImport(from: importer, asOf: today)
        }
    }

    /// Runs `operation` after waiting for whatever's already in ``pendingImport``, and leaves this
    /// call as the new ``pendingImport`` for the next one to wait on. `previous`'s error (if any) is
    /// swallowed, not rethrown — a prior import failing shouldn't prevent this one from running.
    ///
    /// Not `private`: also used by ``TrainingModel/deduplicateActivities(asOf:)`` (a plain store
    /// operation with no `ActivityImporting` dependency, hence its own file) to serialize against
    /// imports the same way two imports serialize against each other.
    func runQueued(_ operation: @escaping () async throws -> Void) async throws {
        let previous = pendingImport
        let task = Task {
            _ = try? await previous?.value
            try await operation()
        }
        pendingImport = task
        try await task.value
    }

    private func performImport(from importer: any ActivityImporting, asOf today: Date) async throws {
        let anchor = try await stores.athleteStore.importAnchor()
        let result = try await importer.importActivities(since: anchor)

        // Captured before deleting: once an activity is gone, the store can no longer answer what
        // day it occupied, and a persisted fitness-metrics cache needs that date to know how far
        // back to invalidate.
        var deletedStarts: [Date] = []
        for source in result.deletedSources {
            if let existing = try await stores.activityStore.activity(source: source) {
                deletedStarts.append(existing.start)
                // Removing a piece dissolves the join it belongs to, which is attributed to the
                // *earliest* piece's day — possibly the day before this piece's, e.g. a session
                // split across midnight — so that day's cached load has to be rebuilt too.
                var removedIDs = [existing.id]
                if let join = try await stores.activityStore.joinedActivity(containing: existing.id) {
                    deletedStarts.append(join.start)
                    removedIDs.append(join.id)
                }
                try await releasePlans(heldBy: removedIDs)
            }
        }

        // A source the athlete already resolved via `deleteActivity(id:)` (MVP1-63/MVP1-64) stays
        // deleted even if `importer` still reports it — without this, every incremental sync (or a
        // full resync) would silently re-insert every duplicate/conflict the athlete had already
        // cleaned up, since the external source has no notion of TrainingKit's own deletes.
        let tombstoned = try await stores.activityStore.tombstonedSources(among: result.upserted.map(\.source))
        let untombstoned = tombstoned.isEmpty ? result.upserted : result.upserted.filter { !tombstoned.contains($0.source) }

        // An importer builds each activity fresh, without the athlete's or reconciler's plan link
        // (see ``Activity/linkedPlanID``); carry an existing link over so a re-import of a changed
        // workout doesn't silently drop a match, including a manual one.
        var toUpsert: [Activity] = untombstoned
        var newActivities: [Activity] = []
        for index in toUpsert.indices {
            if let existing = try await stores.activityStore.activity(id: toUpsert[index].id) {
                if toUpsert[index].linkedPlanID == nil { toUpsert[index].linkedPlanID = existing.linkedPlanID }
            } else {
                newActivities.append(toUpsert[index])
            }
        }

        var refreshedJoinDays: [Date] = []
        if !toUpsert.isEmpty {
            try await stores.activityStore.upsert(toUpsert)
            // A re-imported piece of a joined session changes what that join should show.
            refreshedJoinDays = try await refreshJoins(containing: toUpsert.map(\.id))
        }
        for source in result.deletedSources {
            try await stores.activityStore.deleteActivity(source: source)
        }
        try await stores.athleteStore.saveImportAnchor(result.anchor)

        // Only brand-new activities are auto-matched, so an activity the athlete unlinked stays
        // unlinked when it's re-imported.
        // Best-effort: the import itself has already landed (and its anchor is saved), so a failure
        // matching plans must not skip the cache invalidation and reload below.
        do {
            try await reconcile(newActivities)
        } catch {
            Logging.dataImport.error("Matching imported activities to plans failed: \(error.localizedDescription)")
        }

        let affectedDates = toUpsert.map(\.start) + deletedStarts + refreshedJoinDays
        if let cache = stores.fitnessMetricsCacheStore, let earliest = affectedDates.min() {
            try? await cache.markDirty(from: earliest)
        }
        // `||=`, not an overwrite: a conformer without incremental-import support is allowed to
        // return a `nil` anchor even on a successful run, and a completed import shouldn't read
        // back as "never imported" just because this particular run didn't produce one.
        hasEverImportedActivities = hasEverImportedActivities || result.anchor != nil

        let range = loadedRange ?? Self.union(of: toUpsert.map { $0.start...$0.start }, fallback: today)
        activities = try await stores.activityStore.activities(in: range)
        loadedRange = range
        await recompute(asOf: today)
    }
}

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
    public func importActivities(from importer: any ActivityImporting, asOf today: Date = .now) async throws {
        let anchor = try await stores.athleteStore.importAnchor()
        let result = try await importer.importActivities(since: anchor)

        if !result.upserted.isEmpty {
            try await stores.activityStore.upsert(result.upserted)
        }
        for source in result.deletedSources {
            try await stores.activityStore.deleteActivity(source: source)
        }
        try await stores.athleteStore.saveImportAnchor(result.anchor)
        // `||=`, not an overwrite: a conformer without incremental-import support is allowed to
        // return a `nil` anchor even on a successful run, and a completed import shouldn't read
        // back as "never imported" just because this particular run didn't produce one.
        hasEverImportedActivities = hasEverImportedActivities || result.anchor != nil

        let range = loadedRange ?? Self.union(of: result.upserted.map { $0.start...$0.start }, fallback: today)
        activities = try await stores.activityStore.activities(in: range)
        loadedRange = range
        await recompute(asOf: today)
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
    public func resyncActivities(from importer: any ActivityImporting, asOf today: Date = .now) async throws {
        try await stores.athleteStore.saveImportAnchor(nil)
        try await importActivities(from: importer, asOf: today)
    }
}

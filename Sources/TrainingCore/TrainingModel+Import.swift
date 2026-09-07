import Foundation

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

        let range = loadedRange ?? Self.union(of: result.upserted.map { $0.start...$0.start }, fallback: today)
        activities = try await stores.activityStore.activities(in: range)
        loadedRange = range
        await recompute(asOf: today)
    }
}

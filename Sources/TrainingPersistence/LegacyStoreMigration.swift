import Foundation
import SwiftData
import TrainingCore

/// Moves a store written before the container was split (MVP2-131) to the split layout, once.
///
/// Until then one CloudKit-synced store held every model. Now the models that carry health
/// information (activities with their heart-rate samples, joins, tombstones, the profile with
/// HealthKit-derived fields) live in a local-only store, and only plans, workouts, cycles, races and
/// the athlete's preferences stay in the synced one (see ``TrainingPersistenceContainer``).
///
/// The synced store keeps its file (`default.store`) and so its CloudKit mirror: opening it with the
/// reduced schema drops the local-only tables locally, which doesn't delete anything in CloudKit.
/// So the local-only rows are copied out first, into `Local.store`, by opening the old file without
/// CloudKit (so nothing is exported or imported meanwhile) and without changing it. Records that
/// were already in iCloud stay there until the athlete deletes the app's iCloud data; nothing here
/// can remove them safely.
///
/// A small state file makes it safe to interrupt: `copied` means `Local.store` holds the copy and the
/// old file may already have lost its local tables, so a rerun must not copy again.
enum LegacyStoreMigration {
    private enum State: String {
        /// The local-only data is in `Local.store`; the split container is next.
        case copied
        /// Nothing is left to do.
        case done
    }

    /// The models the unsplit store held, for opening an old file: every current type except the
    /// preferences record, which didn't exist.
    private static var legacyModelTypes: [any PersistentModel.Type] {
        TrainingPersistenceContainer.modelTypes.filter { $0 != AthletePreferencesRecord.self }
    }

    private static func stateURL(in directory: URL) -> URL { directory.appending(path: "split-migration-state") }
    static func syncedStoreURL(in directory: URL) -> URL { directory.appending(path: "default.store") }
    static func localStoreURL(in directory: URL) -> URL { directory.appending(path: "Local.store") }

    private static func state(in directory: URL) -> State? {
        (try? String(contentsOf: stateURL(in: directory), encoding: .utf8)).flatMap { State(rawValue: $0) }
    }

    private static func setState(_ state: State, in directory: URL) throws {
        try state.rawValue.write(to: stateURL(in: directory), atomically: true, encoding: .utf8)
    }

    /// Step one, before the split container is opened: copies the old store's local-only data into
    /// `Local.store` if there is an old store that hasn't been migrated.
    ///
    /// - Parameter directory: Where the store files live.
    /// - Throws: Whatever opening or saving a store throws; nothing is lost, and the next launch
    ///   starts again, since the old file is only read.
    static func copyLocalDataIfNeeded(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch state(in: directory) {
        case .done, .copied:
            return
        case nil:
            guard FileManager.default.fileExists(atPath: syncedStoreURL(in: directory).path) else {
                // A fresh install: there's nothing to carry over, and the file the split container
                // is about to create must not be taken for an old one later.
                try setState(.done, in: directory)
                return
            }
        }

        let legacy = try ModelContainer(
            for: Schema(legacyModelTypes),
            configurations: [ModelConfiguration(
                "default", schema: Schema(legacyModelTypes), url: syncedStoreURL(in: directory), cloudKitDatabase: .none
            )]
        )
        let local = try ModelContainer(
            for: Schema(TrainingPersistenceContainer.localModelTypes),
            configurations: [ModelConfiguration(
                "Local", schema: Schema(TrainingPersistenceContainer.localModelTypes),
                url: localStoreURL(in: directory), cloudKitDatabase: .none
            )]
        )
        try copy(from: ModelContext(legacy), to: ModelContext(local))
        try setState(.copied, in: directory)
    }

    /// Step two, once the split container is open: gives the synced store the athlete's preferences,
    /// taken from the profile that was copied locally, then marks the migration done.
    ///
    /// - Parameters:
    ///   - container: The split container.
    ///   - directory: Where the store files live.
    static func finish(in container: ModelContainer, directory: URL) throws {
        guard state(in: directory) == .copied else { return }
        let context = ModelContext(container)
        if try context.fetch(FetchDescriptor<AthletePreferencesRecord>()).isEmpty,
           let profile = try context.fetch(FetchDescriptor<AthleteProfileRecord>()).first?.toProfile() {
            context.insert(try AthletePreferencesRecord(preferences: AthletePreferences(of: profile)))
            try context.save()
        }
        try setState(.done, in: directory)
    }

    /// Replaces the local-only rows in `destination` with copies of those in `source`. The fitness
    /// metrics cache isn't copied: it's rebuilt from the activities.
    private static func copy(from source: ModelContext, to destination: ModelContext) throws {
        // Idempotent: a copy interrupted before the state was written starts from nothing.
        try destination.delete(model: ActivityRecord.self)
        try destination.delete(model: DeletedActivitySourceRecord.self)
        try destination.delete(model: ActivityJoinRecord.self)
        try destination.delete(model: AthleteProfileRecord.self)

        for record in try source.fetch(FetchDescriptor<ActivityRecord>()) {
            destination.insert(ActivityRecord(
                id: record.id, sourceKey: record.sourceKey, start: record.start, payload: record.payload
            ))
        }
        for record in try source.fetch(FetchDescriptor<DeletedActivitySourceRecord>()) {
            destination.insert(DeletedActivitySourceRecord(sourceKey: record.sourceKey, deletedAt: record.deletedAt))
        }
        for record in try source.fetch(FetchDescriptor<ActivityJoinRecord>()) {
            destination.insert(ActivityJoinRecord(joinID: record.joinID, componentsPayload: record.componentsPayload))
        }
        for record in try source.fetch(FetchDescriptor<AthleteProfileRecord>()) {
            destination.insert(AthleteProfileRecord(
                profilePayload: record.profilePayload, importAnchorData: record.importAnchorData
            ))
        }
        try destination.save()
    }
}

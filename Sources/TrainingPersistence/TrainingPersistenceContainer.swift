import Foundation
import SwiftData

/// Builds the `ModelContainer` covering every model type `TrainingPersistence` persists.
public enum TrainingPersistenceContainer {
    /// The models that sync through CloudKit (MVP2-131): what the athlete plans and chooses, none of
    /// it health information.
    public static var syncedModelTypes: [any PersistentModel.Type] {
        [
            PlannedActivityRecord.self,
            StructuredWorkoutRecord.self,
            TrainingCycleRecord.self,
            RaceRecord.self,
            AthletePreferencesRecord.self,
        ]
    }

    /// The models that stay on the device (MVP2-131): everything read from or derived from HealthKit,
    /// since Apple's guideline 5.1.3(ii) forbids storing health information in iCloud. Activities
    /// carry heart-rate samples; the profile carries sex, date of birth and heart-rate settings; the
    /// fitness metrics are computed from both.
    public static var localModelTypes: [any PersistentModel.Type] {
        [
            ActivityRecord.self,
            DeletedActivitySourceRecord.self,
            ActivityJoinRecord.self,
            AthleteProfileRecord.self,
            FitnessMetricsRecord.self,
            FitnessMetricsCacheStateRecord.self,
        ]
    }

    /// Every model type this package persists, for building a `Schema`/`ModelContainer` that
    /// includes all of them together — they share one container since ``SwiftDataStore`` is one
    /// actor over all the store protocols. ``syncedModelTypes`` and ``localModelTypes`` partition it.
    public static var modelTypes: [any PersistentModel.Type] {
        syncedModelTypes + localModelTypes
    }

    /// Builds the `ModelContainer` covering every model type this package persists, as two stores
    /// (MVP2-131): ``syncedModelTypes`` in a CloudKit-synced one, ``localModelTypes`` in a local-only
    /// one. They share the container, so ``SwiftDataStore`` and its one context see both.
    ///
    /// The first launch on a store written before the split moves its local-only data across (see
    /// `LegacyStoreMigration`).
    ///
    /// - Parameters:
    ///   - cloudKitDatabase: What the *synced* store uses; the local-only store never syncs. Defaults to
    ///     `.automatic`, syncing via the app's default CloudKit container (set up via the app
    ///     target's own iCloud entitlement — this package has no opinion on which container). Pass
    ///     `.none` for a fully local container. Container creation
    ///     succeeds either way even without the entitlement in place — SwiftData doesn't validate
    ///     CloudKit connectivity synchronously at init, only once it actually attempts to sync — so
    ///     a missing entitlement shows up later as silent/logged sync failures, not as a thrown
    ///     error here. Add the capability before shipping if `.automatic` is what you want; don't
    ///     rely on this throwing to tell you it's missing.
    ///
    ///     Background sync while the app isn't foregrounded also needs the app target's
    ///     `UIBackgroundModes` to include `remote-notification`. No additional app code is
    ///     required beyond that: `.automatic` sync is backed by `NSPersistentCloudKitContainer`,
    ///     which registers for and consumes CloudKit's silent push notifications internally — the
    ///     app doesn't need a `UIApplicationDelegate`/`registerForRemoteNotifications()` of its
    ///     own for this. If a future app target ever adds its own remote-notification handling
    ///     for an unrelated reason, make sure it doesn't swallow the push before the system
    ///     forwards it to Core Data's internal handler.
    ///   - isStoredInMemoryOnly: `true` for a throwaway container (tests, previews) that never
    ///     touches disk; defaults to `false`.
    ///   - storeDirectory: Where the two store files live; defaults to the app's Application Support
    ///     directory, where SwiftData puts its default store. Ignored when `isStoredInMemoryOnly`.
    /// - Returns: A `ModelContainer` ready to build a ``SwiftDataStore`` from.
    /// - Throws: Whatever `ModelContainer.init(for:configurations:)` throws — most commonly a
    ///   schema mismatch against an existing on-disk store — or what migrating an old store throws.
    public static func make(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic,
        isStoredInMemoryOnly: Bool = false,
        storeDirectory: URL? = nil
    ) throws -> ModelContainer {
        let directory = storeDirectory ?? URL.applicationSupportDirectory
        if !isStoredInMemoryOnly {
            try LegacyStoreMigration.copyLocalDataIfNeeded(in: directory)
        }
        let container = try makeSplitContainer(
            cloudKitDatabase: cloudKitDatabase, isStoredInMemoryOnly: isStoredInMemoryOnly, directory: directory
        )
        if !isStoredInMemoryOnly {
            try LegacyStoreMigration.finish(in: container, directory: directory)
        }
        try backfillActivityStartIfNeeded(in: container)
        return container
    }

    /// The two-store container itself, without migrating anything: the step ``make(cloudKitDatabase:isStoredInMemoryOnly:storeDirectory:)``
    /// takes between copying an old store's local data and finishing the migration.
    static func makeSplitContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase, isStoredInMemoryOnly: Bool, directory: URL
    ) throws -> ModelContainer {
        let syncedSchema = Schema(syncedModelTypes)
        let localSchema = Schema(localModelTypes)
        // The synced store keeps the name and file of the single store this package used to make, so
        // its CloudKit mirror carries on unchanged.
        let synced = isStoredInMemoryOnly
            ? ModelConfiguration("default", schema: syncedSchema, isStoredInMemoryOnly: true, cloudKitDatabase: cloudKitDatabase)
            : ModelConfiguration(
                "default", schema: syncedSchema, url: LegacyStoreMigration.syncedStoreURL(in: directory),
                cloudKitDatabase: cloudKitDatabase
            )
        let local = isStoredInMemoryOnly
            ? ModelConfiguration("Local", schema: localSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(
                "Local", schema: localSchema, url: LegacyStoreMigration.localStoreURL(in: directory),
                cloudKitDatabase: .none
            )
        return try ModelContainer(for: Schema(modelTypes), configurations: [synced, local])
    }

    /// One-time repair for `ActivityRecord` rows that predate its `start` column.
    ///
    /// SwiftData's automatic lightweight migration fills a newly added attribute with its default
    /// value for every row that already existed on disk — it has no way to derive `start` from
    /// `payload` the way ``ActivityRecord/init(activity:)`` does. Left alone, every activity
    /// imported before `start` existed would keep the sentinel default forever, silently
    /// disappearing from ``SwiftDataStore/activities(in:)``'s range predicate (which only matches
    /// real dates) without ever throwing or logging anything.
    ///
    /// Finds rows still at that sentinel and re-derives `start` from their decoded `payload`,
    /// exactly what a fresh `upsert` would have written. Idempotent and cheap after the first
    /// repaired launch: only rows still carrying the sentinel are ever fetched or decoded, so this
    /// doesn't reintroduce the full-table decode ``activities(in:)`` was fixed to avoid. A row
    /// whose `payload` fails to decode is left as-is rather than failing the whole container's
    /// startup over one corrupt record.
    static func backfillActivityStartIfNeeded(in container: ModelContainer) throws {
        let sentinel = Date(timeIntervalSince1970: 0)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.start == sentinel })
        let staleRecords = try context.fetch(descriptor)
        guard !staleRecords.isEmpty else { return }

        for record in staleRecords {
            guard let start = try? record.toActivity().start else { continue }
            record.start = start
        }
        try context.save()
    }
}

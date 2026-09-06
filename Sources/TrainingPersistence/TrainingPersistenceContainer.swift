import SwiftData

/// Builds the `ModelContainer` covering every model type `TrainingPersistence` persists.
public enum TrainingPersistenceContainer {
    /// Every model type this package persists, for building a `Schema`/`ModelContainer` that
    /// includes all of them together — they share one container since ``SwiftDataStore`` is one
    /// actor over all five store protocols.
    public static var modelTypes: [any PersistentModel.Type] {
        [
            ActivityRecord.self,
            PlannedActivityRecord.self,
            StructuredWorkoutRecord.self,
            TrainingCycleRecord.self,
            AthleteProfileRecord.self,
        ]
    }

    /// Builds a `ModelContainer` covering every model type this package persists.
    ///
    /// - Parameters:
    ///   - cloudKitDatabase: Defaults to `.automatic`, syncing via the app's default CloudKit
    ///     container (set up via the app target's own iCloud entitlement — this package has no
    ///     opinion on which container). Pass `.none` for a local-only store — required for tests
    ///     and previews, and for any target that hasn't added the iCloud/CloudKit capability yet:
    ///     `.automatic` without that entitlement throws here rather than silently falling back to
    ///     local storage.
    ///   - isStoredInMemoryOnly: `true` for a throwaway container (tests, previews) that never
    ///     touches disk; defaults to `false`.
    /// - Returns: A `ModelContainer` ready to build a ``SwiftDataStore`` from.
    /// - Throws: Whatever `ModelContainer.init(for:configurations:)` throws — most commonly a
    ///   missing iCloud/CloudKit entitlement (see `cloudKitDatabase` above) or a schema mismatch
    ///   against an existing on-disk store.
    public static func make(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

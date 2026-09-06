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
    ///     opinion on which container). Pass `.none` for a local-only store. Container creation
    ///     succeeds either way even without the entitlement in place — SwiftData doesn't validate
    ///     CloudKit connectivity synchronously at init, only once it actually attempts to sync — so
    ///     a missing entitlement shows up later as silent/logged sync failures, not as a thrown
    ///     error here. Add the capability before shipping if `.automatic` is what you want; don't
    ///     rely on this throwing to tell you it's missing.
    ///   - isStoredInMemoryOnly: `true` for a throwaway container (tests, previews) that never
    ///     touches disk; defaults to `false`.
    /// - Returns: A `ModelContainer` ready to build a ``SwiftDataStore`` from.
    /// - Throws: Whatever `ModelContainer.init(for:configurations:)` throws — most commonly a
    ///   schema mismatch against an existing on-disk store.
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

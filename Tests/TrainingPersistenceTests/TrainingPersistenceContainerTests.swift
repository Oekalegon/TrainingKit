import Foundation
import SwiftData
import Testing
@testable import TrainingPersistence
import TrainingCore

@Suite("TrainingPersistenceContainer")
struct TrainingPersistenceContainerTests {
    @Test("make(cloudKitDatabase: .none) builds a usable in-memory container")
    func makeLocalOnlyContainer() throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        _ = SwiftDataStore(modelContainer: container)
    }

    @Test("backfillActivityStartIfNeeded re-derives start for a record left at the migration sentinel")
    func backfillCorrectsRecordsLeftAtSentinelByLightweightMigration() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        // Simulates what SwiftData's automatic lightweight migration actually does to a row that
        // existed before ActivityRecord.start was added: the column is backfilled with its default
        // (the sentinel), never with a value derived from `payload` -- so this is built directly
        // via the raw init rather than ActivityRecord(activity:), which would set `start` correctly
        // and wouldn't reproduce the bug.
        let activity = Activity(source: .manual, sport: .running, start: Date(timeIntervalSince1970: 1_700_000_000), duration: 1800)
        let payload = try PersistenceCoding.encode(activity)
        let staleRecord = ActivityRecord(
            id: activity.id,
            sourceKey: activity.source.persistenceKey,
            start: Date(timeIntervalSince1970: 0),
            payload: payload
        )
        context.insert(staleRecord)
        try context.save()

        let store = SwiftDataStore(modelContainer: container)
        let beforeBackfill = try await store.activities(in: activity.start...activity.start)
        #expect(beforeBackfill.isEmpty)

        try TrainingPersistenceContainer.backfillActivityStartIfNeeded(in: container)

        let afterBackfill = try await store.activities(in: activity.start...activity.start)
        #expect(afterBackfill.map(\.id) == [activity.id])
    }

    @Test("backfillActivityStartIfNeeded leaves an already-correct record untouched")
    func backfillIsANoOpForRecordsAlreadyCorrect() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let activity = Activity(source: .manual, sport: .running, start: Date(timeIntervalSince1970: 1_700_000_000), duration: 1800)
        try await store.upsert([activity])

        try TrainingPersistenceContainer.backfillActivityStartIfNeeded(in: container)

        let fetched = try await store.activities(in: activity.start...activity.start)
        #expect(fetched == [activity])
    }

    @Test("make(cloudKitDatabase: .automatic) doesn't throw even without an iCloud/CloudKit entitlement")
    func makeCloudKitContainerDoesNotThrowWithoutEntitlement() throws {
        // This test process has no iCloud/CloudKit capability configured, which is exactly the
        // scenario TrainingPersistenceContainer.make's doc comment describes: SwiftData doesn't
        // validate CloudKit connectivity synchronously at container-creation time, so `.automatic`
        // still succeeds here. A missing entitlement in a real app instead surfaces later, as a
        // silent/logged sync failure once SwiftData actually attempts to talk to CloudKit -- not
        // as a thrown error from this call. This test exists to keep that documented claim honest;
        // actual CloudKit sync itself needs a real device/entitlement and isn't exercised here.
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .automatic, isStoredInMemoryOnly: true)
        _ = SwiftDataStore(modelContainer: container)
    }

    @Test("modelTypes includes the fitness-metrics cache's two model types")
    func modelTypesIncludesFitnessMetricsCacheModels() {
        let types = TrainingPersistenceContainer.modelTypes.map { String(describing: $0) }
        #expect(types.contains("FitnessMetricsRecord"))
        #expect(types.contains("FitnessMetricsCacheStateRecord"))
    }
}

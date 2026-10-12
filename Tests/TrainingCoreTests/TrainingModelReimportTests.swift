import Foundation
import Testing
@testable import TrainingCore

/// What a re-import keeps of an activity it already has (MVP2-146).
@MainActor
@Suite("TrainingModel re-import", .serialized)
struct TrainingModelReimportTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    private func activity(id: UUID, speed: [SpeedSample], heartRate: [HeartRateSample]) -> Activity {
        Activity(
            id: id, source: .healthKit(id), sport: .running, start: day(0), duration: 600,
            heartRate: heartRate, speed: speed
        )
    }

    @Test("a re-import that comes back with no speed or heart rate keeps what was stored")
    func emptyStreamsKeepStored() async throws {
        let (store, model) = makeModel()
        let id = UUID()
        let speed = [SpeedSample(time: day(0), metersPerSecond: 3), SpeedSample(time: day(0).addingTimeInterval(5), metersPerSecond: 3)]
        let heartRate = [HeartRateSample(time: day(0), bpm: 140)]
        try await model.importActivities(from: StubImporter(activities: [activity(id: id, speed: speed, heartRate: heartRate)]), asOf: day(0))

        // The next run's queries failed, or access was refused: both streams are empty.
        try await model.importActivities(from: StubImporter(activities: [activity(id: id, speed: [], heartRate: [])]), asOf: day(0))

        let stored = try #require(try await store.activity(id: id))
        #expect(stored.speed == speed)
        #expect(stored.heartRate == heartRate)
    }

    @Test("a re-import with new streams replaces the stored ones")
    func newStreamsReplace() async throws {
        let (store, model) = makeModel()
        let id = UUID()
        let first = [SpeedSample(time: day(0), metersPerSecond: 3)]
        let second = [SpeedSample(time: day(0), metersPerSecond: 4)]
        try await model.importActivities(from: StubImporter(activities: [activity(id: id, speed: first, heartRate: [])]), asOf: day(0))

        try await model.importActivities(from: StubImporter(activities: [activity(id: id, speed: second, heartRate: [])]), asOf: day(0))

        #expect(try await store.activity(id: id)?.speed == second)
    }
}

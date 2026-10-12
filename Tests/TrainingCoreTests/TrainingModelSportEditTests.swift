import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel sport and venue editing", .serialized)
struct TrainingModelSportEditTests {
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

    @Test("setSport changes the stored and loaded activity and marks it edited")
    func setSportChangesActivity() async throws {
        let (store, model) = makeModel()
        let activity = Activity(source: .healthKit(UUID()), sport: .running, venue: .outdoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))

        try await model.setSport(.running, venue: .indoor(.treadmill), forActivityID: activity.id, asOf: day(0))

        let stored = try #require(try await store.activity(id: activity.id))
        #expect(stored.venue == .indoor(.treadmill))
        #expect(stored.isSportEdited)
        #expect(model.activities.first?.venue == .indoor(.treadmill))
    }

    @Test("a re-import keeps the sport and venue the athlete chose")
    func reimportKeepsEdit() async throws {
        let (store, model) = makeModel()
        let source = ActivitySource.healthKit(UUID())
        let id = UUID()
        let original = Activity(id: id, source: source, sport: .running, venue: .outdoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [original]), asOf: day(0))
        try await model.setSport(.hiking, venue: .outdoor(.trail), forActivityID: id, asOf: day(0))

        try await model.importActivities(from: StubImporter(activities: [original]), asOf: day(0))

        let stored = try #require(try await store.activity(id: id))
        #expect(stored.sport == .hiking)
        #expect(stored.venue == .outdoor(.trail))
    }

    @Test("an unedited activity still takes the source's venue on re-import, and setSport on a missing id does nothing")
    func uneditedFollowsSource() async throws {
        let (store, model) = makeModel()
        let id = UUID()
        let source = ActivitySource.healthKit(UUID())
        try await model.importActivities(
            from: StubImporter(activities: [Activity(id: id, source: source, sport: .running, start: day(0), duration: 1800)]), asOf: day(0)
        )
        try await model.importActivities(
            from: StubImporter(activities: [Activity(id: id, source: source, sport: .running, venue: .indoor(nil), start: day(0), duration: 1800)]),
            asOf: day(0)
        )
        #expect(try await store.activity(id: id)?.venue == .indoor(nil))

        try await model.setSport(.cycling, venue: nil, forActivityID: UUID(), asOf: day(0))
        #expect(try await store.activity(id: id)?.sport == .running)
    }
}

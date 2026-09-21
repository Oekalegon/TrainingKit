import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel join/unjoin", .serialized)
struct TrainingModelJoinTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    private func piece(_ offset: TimeInterval, _ duration: TimeInterval, distance: Double? = nil) -> Activity {
        Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0).addingTimeInterval(offset),
            duration: duration, distanceMeters: distance, perceivedExertion: 5
        )
    }

    @Test("joinActivities shows one joined activity, keeps the originals in the store, and counts load once (MVP1-80)")
    func joinShowsOneActivity() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 343, distance: 668)
        let b = piece(360, 2643, distance: 5200)
        try await store.upsert([a, b])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let loadBefore = model.metrics.map(\.load).reduce(0, +)

        try await model.joinActivities(a.id, b.id, asOf: day(0))

        #expect(model.activities.count == 1)
        #expect(model.activities.first?.distanceMeters == 5868)
        #expect(model.activities.first?.duration == 3003)
        // Originals are untouched and still findable, still tied to their sources.
        #expect(try await store.activity(id: a.id) == a)
        #expect(try await store.activity(id: b.id) == b)
        #expect(try await model.components(ofJoinedActivity: model.activities[0].id).map(\.id) == [a.id, b.id])
        // The fitness series sees the joined session only: no double-counting of the pieces.
        let loadAfter = model.metrics.map(\.load).reduce(0, +)
        #expect(loadBefore > 0)
        #expect(abs(loadAfter - loadBefore) < 5)  // only the ~17 s gap between pieces is added
    }

    @Test("A re-import that redelivers a piece keeps it hidden behind the join, not resurrected (MVP1-80)")
    func reimportKeepsPieceHidden() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 343)
        let b = piece(360, 2643)
        try await store.upsert([a, b])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        try await model.joinActivities(a.id, b.id, asOf: day(0))

        var redelivered = a
        redelivered.distanceMeters = 700
        let importer = FakeImporter(result: ImportResult(upserted: [redelivered], deletedSources: [], anchor: nil))
        try await model.importActivities(from: importer, asOf: day(0))

        #expect(model.activities.count == 1)
        #expect(model.activities.first?.id != a.id)
        #expect(try await store.activity(id: a.id)?.distanceMeters == 700)
    }

    @Test("unjoinActivity restores the original pieces (MVP1-80)")
    func unjoinRestoresPieces() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 343)
        let b = piece(360, 2643)
        try await store.upsert([a, b])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        try await model.joinActivities(a.id, b.id, asOf: day(0))
        let joinedID = try #require(model.activities.first?.id)

        try await model.unjoinActivity(id: joinedID, asOf: day(0))

        #expect(Set(model.activities.map(\.id)) == [a.id, b.id])
        #expect(try await store.activity(id: joinedID) == nil)
    }

    @Test("Joining a third piece onto a joined pair flattens into one join of three (MVP1-80)")
    func joinFlattens() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 300)
        let b = piece(320, 600)
        let c = piece(950, 900)
        try await store.upsert([a, b, c])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        try await model.joinActivities(a.id, b.id, asOf: day(0))
        let firstJoinID = try #require(model.activities.first { $0.id != c.id }?.id)

        try await model.joinActivities(firstJoinID, c.id, asOf: day(0))

        #expect(model.activities.count == 1)
        let joinID = try #require(model.activities.first?.id)
        #expect(try await model.components(ofJoinedActivity: joinID).map(\.id) == [a.id, b.id, c.id])
        #expect(try await store.activity(id: firstJoinID) == nil)
        #expect(model.activities.first?.duration == 1850)
    }

    @Test("Deleting a joined activity deletes and tombstones its pieces (MVP1-80)")
    func deleteJoinedDeletesPieces() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 343)
        let b = piece(360, 2643)
        try await store.upsert([a, b])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        try await model.joinActivities(a.id, b.id, asOf: day(0))
        let joinedID = try #require(model.activities.first?.id)

        try await model.deleteActivity(id: joinedID, asOf: day(0))

        #expect(model.activities.isEmpty)
        #expect(try await store.activity(id: a.id) == nil)
        #expect(try await store.tombstonedSources(among: [a.source, b.source]) == [a.source, b.source])
    }

    @Test("Same id twice, or a missing id, is a no-op (MVP1-80)")
    func noOps() async throws {
        let (store, model) = makeModel()
        let a = piece(0, 343)
        try await store.upsert([a])
        try await model.load(in: day(0)...day(1), asOf: day(0))

        try await model.joinActivities(a.id, a.id, asOf: day(0))
        try await model.joinActivities(a.id, UUID(), asOf: day(0))
        try await model.unjoinActivity(id: a.id, asOf: day(0))

        #expect(model.activities == [a])
    }
}

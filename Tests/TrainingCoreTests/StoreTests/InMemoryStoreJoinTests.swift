import Foundation
import Testing
@testable import TrainingCore

@Suite("InMemoryStore joined activities")
struct InMemoryStoreJoinTests {
    private func makeStore() throws -> InMemoryStore { InMemoryStore() }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func piece(_ offset: TimeInterval, _ duration: TimeInterval) -> Activity {
        Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0).addingTimeInterval(offset),
            duration: duration
        )
    }

    @Test("saveJoin hides the components from activities(in:) but not from id/source lookups")
    func saveJoinHidesComponents() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)

        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        #expect(try await store.activities(in: day(0)...day(1)).map(\.id) == [joined.id])
        #expect(try await store.activity(id: a.id) == a)
        #expect(try await store.activity(source: b.source) == b)
        #expect(try await store.components(ofJoinedActivity: joined.id).map(\.id) == [a.id, b.id])
        #expect(try await store.components(ofJoinedActivity: a.id).isEmpty)
    }

    @Test("A range that only reaches the later component still returns the joined activity, not that piece")
    func rangeBoundaryShowsJoin() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        let laterOnly = day(0).addingTimeInterval(310)...day(0).addingTimeInterval(400)

        #expect(try await store.activities(in: laterOnly).map(\.id) == [joined.id])
    }

    @Test("Re-upserting a component (a re-import) keeps it hidden")
    func reimportKeepsHidden() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        var redelivered = a
        redelivered.distanceMeters = 1
        try await store.upsert([redelivered])

        #expect(try await store.activities(in: day(0)...day(1)).map(\.id) == [joined.id])
    }

    @Test("unjoinActivity removes the joined activity and reveals the components again")
    func unjoin() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        try await store.unjoinActivity(id: joined.id)

        #expect(Set(try await store.activities(in: day(0)...day(1)).map(\.id)) == [a.id, b.id])
        #expect(try await store.activity(id: joined.id) == nil)
    }

    @Test("saveJoin replacing an existing join removes the old joined activity and link")
    func replacing() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        let c = piece(950, 900)
        try await store.upsert([a, b, c])
        let first = Activity.joined(a, b)
        try await store.saveJoin(first, components: [a.id, b.id], replacing: [])
        let second = Activity.joined(first, c)

        try await store.saveJoin(second, components: [a.id, b.id, c.id], replacing: [first.id])

        #expect(try await store.activities(in: day(0)...day(1)).map(\.id) == [second.id])
        #expect(try await store.activity(id: first.id) == nil)
        #expect(try await store.components(ofJoinedActivity: second.id).map(\.id) == [a.id, b.id, c.id])
    }

    @Test("deleteActivity(id:) on a joined activity deletes and tombstones its components")
    func deleteJoined() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        try await store.deleteActivity(id: joined.id)

        #expect(try await store.activities(in: day(0)...day(1)).isEmpty)
        #expect(try await store.activity(id: a.id) == nil)
        #expect(try await store.tombstonedSources(among: [a.source, b.source]) == [a.source, b.source])
    }

    @Test("A component deleted at its origin dissolves the join, so the surviving piece reappears")
    func originDeleteDissolvesJoin() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        try await store.deleteActivity(source: a.source)

        #expect(try await store.activities(in: day(0)...day(1)).map(\.id) == [b.id])
        #expect(try await store.activity(id: joined.id) == nil)
    }
}

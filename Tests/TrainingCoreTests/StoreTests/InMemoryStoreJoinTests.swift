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

    @Test("saveJoin rejects a component that already belongs to another join, and stores nothing")
    func rejectsAlreadyJoinedComponent() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        let c = piece(950, 900)
        try await store.upsert([a, b, c])
        let first = Activity.joined(a, b)
        try await store.saveJoin(first, components: [a.id, b.id], replacing: [])
        let second = Activity.joined(b, c)

        await #expect(throws: ActivityJoinError.componentAlreadyJoined(b.id)) {
            try await store.saveJoin(second, components: [b.id, c.id], replacing: [])
        }

        #expect(try await store.activity(id: second.id) == nil)
        #expect(Set(try await store.activities(in: day(0)...day(1)).map(\.id)) == [first.id, c.id])
    }

    @Test("joinedActivity(containing:) finds the join of a piece, and nil for anything else")
    func joinedActivityContaining() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        let lone = piece(5000, 300)
        try await store.upsert([a, b, lone])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])

        #expect(try await store.joinedActivity(containing: b.id)?.id == joined.id)
        #expect(try await store.joinedActivity(containing: lone.id) == nil)
    }

    @Test("saveJoin under an existing join's own id rebuilds it in place")
    func rebuildInPlace() async throws {
        let store = try makeStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let joined = Activity.joined(a, b)
        try await store.saveJoin(joined, components: [a.id, b.id], replacing: [])
        var corrected = a
        corrected.distanceMeters = 1000
        try await store.upsert([corrected])

        let rebuilt = try #require(Activity.joined([corrected, b], id: joined.id))
        try await store.saveJoin(rebuilt, components: [a.id, b.id], replacing: [])

        let shown = try await store.activities(in: day(0)...day(1))
        #expect(shown.map(\.id) == [joined.id])
        #expect(shown.first?.distanceMeters == 1000)
    }

    @Test("Deleting one of two joins that share a piece (e.g. synced from two devices) keeps the shared piece")
    func deleteKeepsSharedPiece() async throws {
        let store = InMemoryStore()
        let a = piece(0, 300)
        let b = piece(320, 600)
        try await store.upsert([a, b])
        let one = Activity.joined(a, b)
        let two = Activity.joined(a, b)
        try await store.upsert([one, two])
        // Two joins over the same pieces can't be built through `saveJoin` (it refuses); this is the
        // state two devices joining independently end up in once CloudKit merges their rows.
        await store.setJoinLinksForTesting([one.id: [a.id, b.id], two.id: [a.id, b.id]])

        try await store.deleteActivity(id: one.id)

        #expect(try await store.activity(id: a.id) == a)
        #expect(try await store.activity(id: b.id) == b)
        #expect(try await store.tombstonedSources(among: [a.source, b.source]).isEmpty)
        #expect(try await store.activities(in: day(0)...day(1)).map(\.id) == [two.id])
    }
}

extension InMemoryStore {
    func setJoinLinksForTesting(_ links: [UUID: [UUID]]) { componentIDsByJoinID = links }
}

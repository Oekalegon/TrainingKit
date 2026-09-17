import Foundation
import Testing
@testable import TrainingCore

@Suite("FitnessMetricsCacheStore (InMemoryStore)")
struct FitnessMetricsCacheStoreTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func metrics(day: Date, load: Double = 50) -> FitnessMetrics {
        FitnessMetrics(
            day: day, load: load, ctl: load, atl: load, tsb: 0,
            monotony: 1, strain: load, isProjected: false, isWarmingUp: false
        )
    }

    @Test("upsert/fetch round-trips and replaces by day rather than duplicating")
    func upsertRoundTrips() async throws {
        let store = InMemoryStore()
        try await store.upsert([metrics(day: day(0), load: 10), metrics(day: day(1), load: 20)])

        let fetched = try await store.cachedMetrics(in: day(0)...day(1))
        #expect(Set(fetched.map(\.day)) == Set([day(0), day(1)]))

        // Same day again: replaces, doesn't duplicate.
        try await store.upsert([metrics(day: day(0), load: 999)])
        let refetched = try await store.cachedMetrics(in: day(0)...day(0))
        #expect(refetched.count == 1)
        #expect(refetched.first?.load == 999)
    }

    @Test("cachedMetrics(immediatelyBefore:) returns the latest day strictly before the given date")
    func immediatelyBeforeBoundary() async throws {
        let store = InMemoryStore()
        try await store.upsert([metrics(day: day(0)), metrics(day: day(1)), metrics(day: day(3))])

        #expect(try await store.cachedMetrics(immediatelyBefore: day(4))?.day == day(3))
        #expect(try await store.cachedMetrics(immediatelyBefore: day(3))?.day == day(1)) // exclusive
        #expect(try await store.cachedMetrics(immediatelyBefore: day(0)) == nil)
    }

    @Test("recentLoads(before:count:) returns the trailing loads, oldest first, capped at count")
    func recentLoadsBoundary() async throws {
        let store = InMemoryStore()
        try await store.upsert([
            metrics(day: day(0), load: 1), metrics(day: day(1), load: 2),
            metrics(day: day(2), load: 3), metrics(day: day(3), load: 4),
        ])

        #expect(try await store.recentLoads(before: day(4), count: 2) == [3, 4])
        #expect(try await store.recentLoads(before: day(4), count: 10) == [1, 2, 3, 4]) // fewer than count available
        #expect(try await store.recentLoads(before: day(0), count: 2) == []) // nothing strictly before day(0)
    }

    @Test("latestCachedDay/earliestCachedDay reflect the stored range, nil when empty")
    func latestAndEarliestCachedDay() async throws {
        let store = InMemoryStore()
        #expect(try await store.latestCachedDay() == nil)
        #expect(try await store.earliestCachedDay() == nil)

        try await store.upsert([metrics(day: day(5)), metrics(day: day(1)), metrics(day: day(3))])
        #expect(try await store.latestCachedDay() == day(5))
        #expect(try await store.earliestCachedDay() == day(1))
    }

    @Test("deleteCachedMetrics(from:) removes every row with day >= date, inclusive")
    func deleteFromBoundary() async throws {
        let store = InMemoryStore()
        try await store.upsert([metrics(day: day(0)), metrics(day: day(1)), metrics(day: day(2))])

        try await store.deleteCachedMetrics(from: day(1))

        let remaining = try await store.cachedMetrics(in: day(0)...day(2))
        #expect(remaining.map(\.day) == [day(0)])
    }

    @Test("markDirty lowers the watermark but never raises it")
    func markDirtyNeverRaisesWatermark() async throws {
        let store = InMemoryStore()
        #expect(try await store.dirtyWatermark() == nil)

        try await store.markDirty(from: day(5))
        #expect(try await store.dirtyWatermark() == day(5))

        try await store.markDirty(from: day(10)) // later — must not raise the watermark
        #expect(try await store.dirtyWatermark() == day(5))

        try await store.markDirty(from: day(2)) // earlier — lowers it
        #expect(try await store.dirtyWatermark() == day(2))
    }

    @Test("clearDirtyWatermark resets to nil")
    func clearDirtyWatermarkResets() async throws {
        let store = InMemoryStore()
        try await store.markDirty(from: day(5))
        try await store.clearDirtyWatermark()
        #expect(try await store.dirtyWatermark() == nil)
    }
}

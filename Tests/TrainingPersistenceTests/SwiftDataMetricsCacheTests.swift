import Foundation
import SwiftData
import Testing
import TrainingCore
@testable import TrainingPersistence

/// The cache-aware recompute against the real `SwiftDataStore` cache (the core suite uses
/// `InMemoryStore`): after a late import across an uncached gap, and after a stale cached row, the
/// published CTL/ATL/TSB must match a from-scratch computation.
@MainActor
@Suite("TrainingModel + SwiftData metrics cache", .serialized)
struct SwiftDataMetricsCacheTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func activity(onDay offset: Int, hour: Int = 9, minutes: Double = 30) -> Activity {
        Activity(
            source: .healthKit(UUID()), sport: .running,
            start: calendar.date(byAdding: .hour, value: hour, to: day(offset))!,
            duration: minutes * 60, perceivedExertion: 5
        )
    }

    private func makeStore() throws -> SwiftDataStore {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        return SwiftDataStore(modelContainer: container)
    }

    private func stores(_ store: SwiftDataStore, cached: Bool) -> StoreSet {
        StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
            raceStore: store, athleteStore: store, fitnessMetricsCacheStore: cached ? store : nil
        )
    }

    private func expectMatchesFromScratch(
        _ model: TrainingModel, store: SwiftDataStore, range: ClosedRange<Date>, today: Date
    ) async throws {
        let reference = TrainingModel(stores: stores(store, cached: false), athlete: model.athlete)
        try await reference.load(in: day(-30)...range.upperBound, asOf: today)
        for want in reference.metrics where range.contains(want.day) {
            let rows = model.metrics.filter { $0.day == want.day }
            #expect(rows.count == 1)
            guard let got = rows.first else { continue }
            #expect(abs(got.ctl - want.ctl) < 1e-6)
            #expect(abs(got.atl - want.atl) < 1e-6)
            #expect(abs(got.tsb - want.tsb) < 1e-6)
        }
    }

    @Test("a late import after the cache fell several days behind matches a from-scratch series")
    func lateImportAfterCacheGap() async throws {
        let store = try makeStore()
        for offset in 0...10 where offset != 5 && offset != 6 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores(store, cached: true), athlete: AthleteProfile.fixture())
        let window = day(8)...day(16)
        try await model.load(in: window, asOf: day(11))

        try await store.upsert([activity(onDay: 11, minutes: 90), activity(onDay: 12, minutes: 75)])
        let late = ImportResult(upserted: [activity(onDay: 13, hour: 21)], deletedSources: [], anchor: nil)
        try await model.importActivities(from: StubImporter(result: late), asOf: day(14))
        try await expectMatchesFromScratch(model, store: store, range: window, today: day(14))
    }

    @Test("a stale cached row is recomputed")
    func staleCachedRowIsHealed() async throws {
        let store = try makeStore()
        for offset in 0...10 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores(store, cached: true), athlete: AthleteProfile.fixture())
        let window = day(4)...day(14)
        try await model.load(in: window, asOf: day(11))

        let good = try #require(try await store.cachedMetrics(in: day(9)...day(9)).first)
        try await store.upsert([
            FitnessMetrics(
                day: good.day, load: good.load, ctl: good.ctl / 3, atl: good.atl / 5, tsb: good.tsb,
                monotony: good.monotony, strain: good.strain, isProjected: false, isWarmingUp: good.isWarmingUp
            ),
        ])
        await model.recompute(asOf: day(11))
        try await expectMatchesFromScratch(model, store: store, range: window, today: day(11))
    }
}

private actor StubImporter: ActivityImporting {
    let result: ImportResult
    init(result: ImportResult) { self.result = result }
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult { result }
}

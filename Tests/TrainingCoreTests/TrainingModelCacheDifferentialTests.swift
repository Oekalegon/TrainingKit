import Foundation
import Testing
@testable import TrainingCore

/// The cache-aware recompute must publish the same CTL/ATL/TSB as a from-scratch computation,
/// however the cache got into its current state.
@MainActor
@Suite("TrainingModel cache vs from-scratch", .serialized)
struct TrainingModelCacheDifferentialTests {
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
        let start = calendar.date(byAdding: .hour, value: hour, to: day(offset))!
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start,
            duration: minutes * 60, perceivedExertion: 5
        )
    }

    private func makeStores(
        activityStore: (any ActivityStore)? = nil, store: InMemoryStore, cache: (any FitnessMetricsCacheStore)?
    ) -> StoreSet {
        StoreSet(
            activityStore: activityStore ?? store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, fitnessMetricsCacheStore: cache
        )
    }

    /// Publishes `model`'s metrics against a fresh, cache-less model over the same stores.
    private func expectMatchesFromScratch(
        _ model: TrainingModel, stores: StoreSet, range: ClosedRange<Date>, today: Date, label: String
    ) async throws {
        // The same stores without a cache: `TrainingModel` then recomputes the whole series from
        // the activities every time, which is the reference the cache has to agree with.
        var uncachedStores = stores
        uncachedStores.fitnessMetricsCacheStore = nil
        let reference = TrainingModel(stores: uncachedStores, athlete: model.athlete)
        // The whole history, not just `range`: the reference has to be warm where `range` starts.
        try await reference.load(in: day(-30)...range.upperBound, asOf: today)

        for want in reference.metrics where range.contains(want.day) {
            let rows = model.metrics.filter { $0.day == want.day }
            #expect(rows.count == 1, Comment(rawValue: "\(label): \(rows.count) rows for day \(want.day)"))
            guard let got = rows.first else { continue }
            #expect(abs(got.ctl - want.ctl) < 1e-6, Comment(rawValue: "\(label): CTL on \(want.day): \(got.ctl) vs \(want.ctl)"))
            #expect(abs(got.atl - want.atl) < 1e-6, Comment(rawValue: "\(label): ATL on \(want.day): \(got.atl) vs \(want.atl)"))
            #expect(abs(got.tsb - want.tsb) < 1e-6, Comment(rawValue: "\(label): TSB on \(want.day): \(got.tsb) vs \(want.tsb)"))
        }
    }

    @Test("a late import after the cache fell several days behind matches a from-scratch series")
    func lateImportAfterCacheGap() async throws {
        let store = InMemoryStore()
        let stores = makeStores(store: store, cache: store)
        for offset in 0...10 where offset != 5 && offset != 6 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        // Last app run: day 11 was "today", so the cache is final through day 10.
        let window = day(8)...day(16)
        try await model.load(in: window, asOf: day(11))

        // Days 11-13 pass with the app closed. The store gains heavy days 11 and 12 (no import
        // marked them dirty), then HealthKit delivers a day-13 activity, so the dirty day is 13
        // while the cache stops at day 10.
        try await store.upsert([activity(onDay: 11, minutes: 90), activity(onDay: 12, minutes: 75)])
        let late = ImportResult(upserted: [activity(onDay: 13, hour: 21)], deletedSources: [], anchor: nil)
        try await model.importActivities(from: StubImporter(result: late), asOf: day(14))
        try await expectMatchesFromScratch(model, stores: stores, range: window, today: day(14), label: "gap")
    }

    @Test("the first pass alone, without the self-heal, seeds from the day before the first uncached one")
    func firstPassDoesNotSkipTheGap() async throws {
        let store = InMemoryStore()
        let stores = makeStores(store: store, cache: store)
        for offset in 0...10 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        try await model.load(in: day(8)...day(16), asOf: day(11))

        // The cache is final through day 10; days 11-13 gain activity and the dirty day is 13.
        try await store.upsert([activity(onDay: 11, minutes: 90), activity(onDay: 12, minutes: 75), activity(onDay: 13)])
        try await store.markDirty(from: day(13))

        // Called directly: `recompute(asOf:)` would repair a bad first pass via the self-heal and
        // hide the very bug this guards against.
        let published = await TrainingModel.buildMetricsWithCache(
            cache: store, stores: stores, publishRange: day(8)...day(16),
            workouts: [], estimator: TRIMPPlanEstimator(),
            calculators: [ExponentialTRIMPCalculator(), DurationRPECalculator()],
            athlete: model.athlete, parameters: LoadModelParameters(), today: day(14),
            mayClearWatermark: { true }
        )
        #expect(TrainingModel.firstInconsistentDay(
            in: published, parameters: LoadModelParameters(), timeZone: TimeZone(identifier: "UTC")!
        ) == nil)

        var uncachedStores = stores
        uncachedStores.fitnessMetricsCacheStore = nil
        let reference = TrainingModel(stores: uncachedStores, athlete: model.athlete)
        try await reference.load(in: day(-30)...day(16), asOf: day(14))
        for want in published {
            let expected = try #require(reference.metrics.first { $0.day == want.day })
            #expect(abs(want.atl - expected.atl) < 1e-6, Comment(rawValue: "ATL on \(want.day): \(want.atl) vs \(expected.atl)"))
        }
    }

    @Test("a dirty watermark with an empty cache rebuilds from the beginning instead of starting cold")
    func watermarkWithEmptyCache() async throws {
        let store = InMemoryStore()
        let stores = makeStores(store: store, cache: store)
        for offset in 0...10 {
            try await store.upsert([activity(onDay: offset)])
        }
        try await store.markDirty(from: day(9))
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        let window = day(6)...day(12)
        try await model.load(in: window, asOf: day(11))
        try await expectMatchesFromScratch(model, stores: stores, range: window, today: day(11), label: "empty cache")
    }

    @Test("cached rows that don't follow from the day before them are recomputed")
    func inconsistentCachedRowsAreHealed() async throws {
        let store = InMemoryStore()
        let stores = makeStores(store: store, cache: store)
        for offset in 0...10 {
            try await store.upsert([activity(onDay: offset)])
        }
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        let window = day(4)...day(14)
        try await model.load(in: window, asOf: day(11))

        // What the old seeding bug left behind: day 9 cached from a stale seed, so it (and, if it
        // had been recomputed, everything after it) disagrees with the day before it.
        let good = try #require(try await store.cachedMetrics(in: day(9)...day(9)).first)
        try await store.upsert([
            FitnessMetrics(
                day: good.day, load: good.load, ctl: good.ctl / 3, atl: good.atl / 5, tsb: good.tsb,
                monotony: good.monotony, strain: good.strain, isProjected: false, isWarmingUp: good.isWarmingUp
            ),
        ])

        await model.recompute(asOf: day(11))
        try await expectMatchesFromScratch(model, stores: stores, range: window, today: day(11), label: "healed")
        let repaired = try #require(try await store.cachedMetrics(in: day(9)...day(9)).first)
        #expect(abs(repaired.ctl - good.ctl) < 1e-6)
    }

    @Test("an invalidation that lands while a recompute is running is not cleared by it")
    func invalidationDuringRecomputeSurvives() async throws {
        let store = InMemoryStore()
        for offset in 0...5 {
            try await store.upsert([activity(onDay: offset)])
        }
        let hookedActivities = HookedFetchActivityStore(wrapping: store)
        let stores = makeStores(activityStore: hookedActivities, store: store, cache: store)
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())

        // The next fetch the recompute makes is where a background import would land.
        await hookedActivities.setOnNextFetch { await model.markCacheDirty(from: self.day(4)) }
        await model.recompute(asOf: day(8))

        #expect(try await store.dirtyWatermark() != nil)
    }

    @Test("a hole in the published series is reported from the day before it")
    func holeIsInconsistent() {
        func row(_ offset: Int, ctl: Double, atl: Double, load: Double) -> FitnessMetrics {
            FitnessMetrics(
                day: day(offset), load: load, ctl: ctl, atl: atl, tsb: 0,
                monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
            )
        }
        let parameters = LoadModelParameters()
        let first = row(0, ctl: 10, atl: 10, load: 10)
        let second = row(
            1, ctl: 10 + (50 - 10) / parameters.ctlTimeConstantDays,
            atl: 10 + (50 - 10) / parameters.atlTimeConstantDays, load: 50
        )
        let zone = TimeZone(identifier: "UTC")!
        #expect(TrainingModel.firstInconsistentDay(in: [first, second], parameters: parameters, timeZone: zone) == nil)
        let skipped = row(3, ctl: second.ctl, atl: second.atl, load: 0)
        #expect(TrainingModel.firstInconsistentDay(in: [first, second, skipped], parameters: parameters, timeZone: zone) == day(1))
    }
}

private actor StubImporter: ActivityImporting {
    let result: ImportResult
    init(result: ImportResult) { self.result = result }
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult { result }
}

/// Forwards to another `ActivityStore`, running a one-shot hook the first time `activities(in:)`
/// is called — a stand-in for an import landing in the middle of a recompute.
private actor HookedFetchActivityStore: ActivityStore {
    private let wrapped: any ActivityStore
    private var onNextFetch: (@Sendable () async -> Void)?

    init(wrapping wrapped: any ActivityStore) { self.wrapped = wrapped }

    func setOnNextFetch(_ hook: @escaping @Sendable () async -> Void) { onNextFetch = hook }

    func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        if let hook = onNextFetch {
            onNextFetch = nil
            await hook()
        }
        return try await wrapped.activities(in: range)
    }
    func upsert(_ activities: [Activity]) async throws {
        try await wrapped.upsert(activities)
    }
    func activity(source: ActivitySource) async throws -> Activity? {
        try await wrapped.activity(source: source)
    }
    func activity(id: UUID) async throws -> Activity? {
        try await wrapped.activity(id: id)
    }
    func deleteActivity(source: ActivitySource) async throws {
        try await wrapped.deleteActivity(source: source)
    }
    func deleteActivity(id: UUID) async throws {
        try await wrapped.deleteActivity(id: id)
    }
    func saveJoin(_ merged: Activity, components: [UUID], replacing replacedJoinIDs: [UUID]) async throws {
        try await wrapped.saveJoin(merged, components: components, replacing: replacedJoinIDs)
    }
    func components(ofJoinedActivity id: UUID) async throws -> [Activity] {
        try await wrapped.components(ofJoinedActivity: id)
    }
    func unjoinActivity(id: UUID) async throws { try await wrapped.unjoinActivity(id: id) }
    func joinedActivity(containing componentID: UUID) async throws -> Activity? {
        try await wrapped.joinedActivity(containing: componentID)
    }
    func tombstonedSources(among sources: [ActivitySource]) async throws -> Set<ActivitySource> {
        try await wrapped.tombstonedSources(among: sources)
    }
    func deduplicateActivities() async throws -> [Activity] {
        try await wrapped.deduplicateActivities()
    }
}

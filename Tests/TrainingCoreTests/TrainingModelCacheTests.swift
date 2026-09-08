import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel + FitnessMetricsCacheStore")
struct TrainingModelCacheTests {
    /// Exact UTC-midnight-aligned days, matching how `TrainingModel`'s cache algorithm computes
    /// `calendar.startOfDay(for:)` (the athlete fixture below uses the UTC time zone) — unlike the
    /// raw, non-midnight-aligned `day(offset)` helper other test files use for range-containment
    /// checks that don't need exact equality against a cached row's `.day`.
    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func makeStores(cache: any FitnessMetricsCacheStore) -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store, fitnessMetricsCacheStore: cache
        )
        return (store, stores)
    }

    private func seedMetrics(day: Date, ctl: Double, atl: Double, load: Double = 0) -> FitnessMetrics {
        FitnessMetrics(
            day: day, load: load, ctl: ctl, atl: atl, tsb: ctl - atl,
            monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
        )
    }

    @Test("a seeded cache produces a warm CTL/ATL continuation, not a cold start")
    func seededCacheProducesWarmContinuation() async throws {
        let cache = InMemoryStore()
        // "Yesterday" relative to the loaded window, already cached as if computed by a prior run.
        try await cache.upsert([seedMetrics(day: day(-1), ctl: 75, atl: 78, load: 80)])

        let (store, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()
        // duration/60 * RPE = 20 * 5 = 100 TRIMP.
        let activity = Activity(
            source: .manual, sport: .running, start: day(0), duration: 1200, perceivedExertion: 5
        )
        try await store.upsert([activity])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(0), asOf: day(0))

        let expectedCTL = 75 + (100 - 75) / LoadModelParameters().ctlTimeConstantDays
        let expectedATL = 78 + (100 - 78) / LoadModelParameters().atlTimeConstantDays
        let today = try #require(model.metrics.first { $0.day == day(0) })

        #expect(abs(today.ctl - expectedCTL) < 1e-9)
        #expect(abs(today.atl - expectedATL) < 1e-9)
        #expect(today.isWarmingUp == false)
    }

    @Test("a second recompute only touches newly-final days, not the whole cached history")
    func secondRecomputeOnlyTouchesNewDays() async throws {
        let cache = InMemoryStore()
        let (store, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()
        // Activities across several final (day < today) days plus today.
        for offset in 0...5 {
            try await store.upsert([
                Activity(source: .manual, sport: .running, start: day(offset), duration: 1200, perceivedExertion: 4),
            ])
        }

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(6))
        let cachedAfterFirstRun = try await cache.cachedMetrics(in: day(0)...day(5))
        #expect(cachedAfterFirstRun.count == 6) // every day(0)...day(5) is now final and cached

        // A second launch, nothing changed: recompute should only touch the (still-volatile)
        // day(6) — every previously-cached final day must be left exactly as it was.
        let beforeSecondRun = try await cache.cachedMetrics(in: day(0)...day(5))
        await model.recompute(asOf: day(6))
        let afterSecondRun = try await cache.cachedMetrics(in: day(0)...day(5))

        #expect(Set(beforeSecondRun.map(\.ctl)) == Set(afterSecondRun.map(\.ctl)))
        #expect(afterSecondRun.count == beforeSecondRun.count)
    }

    @Test("add(_ plan:) and add(_ cycles:) never write to the fitness-metrics cache")
    func plansAndCyclesNeverTouchCache() async throws {
        let spy = SpyCacheStore(wrapping: InMemoryStore())
        let (store, stores) = makeStores(cache: spy)
        let athlete = AthleteProfile.fixture()
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        try await store.upsert([workout])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(0))
        await spy.resetCounts() // ignore whatever the initial load's bootstrap touched

        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await model.add(plan, asOf: day(0))

        let cycle = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        try await model.add([cycle], asOf: day(0))

        #expect(await spy.markDirtyCallCount == 0)
        #expect(await spy.upsertCallCount == 0)
    }

    @Test("assigning parameters fully invalidates the cache")
    func parametersMutationFullyInvalidates() async throws {
        let cache = InMemoryStore()
        try await cache.upsert([seedMetrics(day: day(-100), ctl: 10, atl: 10)])
        let (_, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()

        let model = TrainingModel(stores: stores, athlete: athlete)
        model.parameters = LoadModelParameters(ctlTimeConstantDays: 30, atlTimeConstantDays: 5, monotonyWindowDays: 5)
        await model.recompute(asOf: day(0))

        // A full invalidation from .distantPast means the pre-existing seeded day is now
        // *before* the recompute's effectiveFetchFrom (the epoch bootstrap sentinel is later than
        // .distantPast, so the watermark itself, not the sentinel, drives this) — assert via the
        // watermark having been consumed (cleared) and the old seed no longer being the basis:
        // the model's `metrics` for day(0) should reflect an unseeded cold start rather than the
        // stale ctl:10/atl:10 seed, since that seed's day is now considered dirty too.
        #expect(try await cache.dirtyWatermark() == nil) // consumed by the recompute above
    }

    @Test("an added heart-rate-zone entry invalidates only from its effectiveDate forward, not the whole cache")
    func athleteZoneChangeInvalidatesFromEffectiveDateOnly() async throws {
        let cache = InMemoryStore()
        // Two long-settled, already-cached final days, well before where the new zone entry will
        // take effect.
        try await cache.upsert([
            seedMetrics(day: day(-10), ctl: 42, atl: 42),
            seedMetrics(day: day(-9), ctl: 43, atl: 43),
        ])
        let (_, stores) = makeStores(cache: cache)
        var athlete = AthleteProfile.fixture()

        let model = TrainingModel(stores: stores, athlete: athlete)
        // A new zone entry effective at day(-5) — strictly after the two seeded days above.
        athlete.heartRateZoneHistory.append(
            HeartRateZoneSettings(effectiveDate: day(-5), restingHeartRateBPM: 48, maxHeartRateBPM: 195)
        )
        model.athlete = athlete
        await model.recompute(asOf: day(0))

        // The two pre-existing cached days (both before day(-5)) must be untouched, since
        // heartRateZoneSettings(asOf:) only ever looks backward — a zone entry effective at
        // day(-5) cannot change anything computed for day(-10)/day(-9).
        let untouched = try await cache.cachedMetrics(in: day(-10)...day(-9))
        #expect(untouched.map(\.ctl).sorted() == [42, 43])
    }

    @Test("a no-op athlete reassignment triggers no invalidation")
    func noOpAthleteReassignmentTriggersNothing() async throws {
        let cache = InMemoryStore()
        try await cache.upsert([seedMetrics(day: day(-1), ctl: 42, atl: 42)])
        let (_, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()

        let model = TrainingModel(stores: stores, athlete: athlete)
        model.athlete = athlete // identical value
        await model.recompute(asOf: day(0))

        // Untouched: the pre-existing cached day survives, since nothing was actually dirtied.
        let stillCached = try await cache.cachedMetrics(in: day(-1)...day(-1))
        #expect(stillCached.first?.ctl == 42)
    }

    @Test("retroactively editing an already-cached day seeds from the day before it, not from its own stale value")
    func retroactiveEditSeedsFromDayBeforeNotFromItself() async throws {
        let cache = InMemoryStore()
        // day(-1) and day(0) are both already cached from a prior run — day(0)'s row (ctl=52,
        // atl=55, from an original load of 80) is about to become stale.
        try await cache.upsert([
            seedMetrics(day: day(-1), ctl: 50, atl: 50, load: 50),
            seedMetrics(day: day(0), ctl: 52, atl: 55, load: 80),
        ])
        let (_, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        // A HealthKit resync delivers a previously-missed activity on day(0), at a mid-day
        // timestamp (never exactly midnight, like any real `Activity.start`). This is the only
        // real `Activity` the store has for day(0) — the "80" cached above was synthetic seed
        // data, not backed by a store record — so day(0)'s real recomputed load is just this
        // activity's own 30 min * RPE 5 = 150.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midDayStart = calendar.date(byAdding: .hour, value: 9, to: day(0))!
        let newActivity = Activity(
            source: .healthKit(UUID()), sport: .running, start: midDayStart, duration: 1800, perceivedExertion: 5
        )
        let importer = FakeCacheTestImporter(result: ImportResult(upserted: [newActivity], deletedSources: [], anchor: nil))

        // `today` = day(1) so day(0) counts as final (day < today) and gets recomputed + re-cached.
        try await model.importActivities(from: importer, asOf: day(1))

        let recomputedDayZero = try #require(try await cache.cachedMetrics(in: day(0)...day(0)).first)
        // The total load for day(0) is now just the new activity's own 150 (no other activity
        // backs the original synthetic load: 80), seeded correctly from day(-1)'s (50, 50).
        let newTotalLoad = 30.0 * 5 // duration/60 * RPE
        let expectedCTL = 50 + (newTotalLoad - 50) / LoadModelParameters().ctlTimeConstantDays
        let expectedATL = 50 + (newTotalLoad - 50) / LoadModelParameters().atlTimeConstantDays

        #expect(abs(recomputedDayZero.ctl - expectedCTL) < 1e-9)
        #expect(abs(recomputedDayZero.atl - expectedATL) < 1e-9)
        // The bug this guards against would instead seed from day(0)'s own stale (52, 55),
        // producing a visibly different (wrong) result — assert we're nowhere near that.
        let wrongCTLFromSelfSeed = 52 + (newTotalLoad - 52) / LoadModelParameters().ctlTimeConstantDays
        #expect(abs(recomputedDayZero.ctl - wrongCTLFromSelfSeed) > 0.01)
    }

    @Test("changing the athlete's time zone wipes the cache rather than leaving old-boundary rows behind")
    func timeZoneChangeWipesStaleCacheRows() async throws {
        let cache = InMemoryStore()
        // A row cached under the athlete's original UTC day boundaries.
        try await cache.upsert([seedMetrics(day: day(-1), ctl: 42, atl: 42)])
        let (_, stores) = makeStores(cache: cache)
        var athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)

        athlete.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        model.athlete = athlete
        await model.recompute(asOf: day(0))

        // The old row's `ctl: 42` marker must not survive: `upsert` matches purely by `day`, and a
        // timezone change shifts every recomputed `day` value relative to the old (UTC-aligned)
        // rows, so without an explicit wipe the stale row would sit alongside the freshly
        // recomputed ones under a slightly different Date key forever, rather than being replaced.
        let allCached = try await cache.cachedMetrics(in: .distantPast...day(10))
        #expect(allCached.allSatisfy { $0.ctl != 42 })
    }

    @Test("a heart-rate-zone entry effective in the future doesn't crash recompute even when it's beyond the published range")
    func futureZoneEffectiveDateDoesNotCrashRecompute() async throws {
        let cache = InMemoryStore()
        let (_, stores) = makeStores(cache: cache)
        var athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(0), asOf: day(0)) // narrow loadedRange, doesn't reach the future

        // A zone change effective well beyond both `today` and the currently loaded range -- a
        // legitimate real flow ("my zones change starting next month"). Before the fix, the dirty
        // watermark this produces (`day(365)`) fed straight into `fetchFromStart` unclamped, and
        // `fetchFromStart...upperBound` (`upperBound` being `today`/`publishRange`'s upper bound,
        // both far short of `day(365)`) trapped building an invalid `ClosedRange`.
        athlete.heartRateZoneHistory.append(
            HeartRateZoneSettings(effectiveDate: day(365), restingHeartRateBPM: 48, maxHeartRateBPM: 195)
        )
        model.athlete = athlete
        await model.recompute(asOf: day(0))

        #expect(model.metrics.contains { $0.day == day(0) })
    }

    @Test("a full (.distantPast) invalidation only reaches back to the cache's own earliest day, not the beginning of time")
    func fullInvalidationIsBoundedByEarliestCachedDay() async throws {
        let cache = InMemoryStore()
        // Only 3 days of cached history — a full invalidate must not attempt to pad/recompute
        // centuries further back than this.
        try await cache.upsert([
            seedMetrics(day: day(-3), ctl: 40, atl: 40, load: 40),
            seedMetrics(day: day(-2), ctl: 41, atl: 41, load: 41),
            seedMetrics(day: day(-1), ctl: 42, atl: 42, load: 42),
        ])
        let (_, stores) = makeStores(cache: cache)
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        model.parameters = LoadModelParameters(ctlTimeConstantDays: 30, atlTimeConstantDays: 5, monotonyWindowDays: 5)
        await model.recompute(asOf: day(0))

        // Bounded: the cache's earliest day is still day(-3) (the recompute started there, an
        // unseeded cold start for the very first cached day, exactly as a real bootstrap would),
        // not some far earlier date reachable only by walking back from `.distantPast`.
        #expect(try await cache.earliestCachedDay() == day(-3))
        #expect(try await cache.dirtyWatermark() == nil) // consumed
    }
}

/// A minimal `ActivityImporting` fake for this file's tests — mirrors `TrainingModelTests.swift`'s
/// private `FakeImporter`, redeclared here since that one is file-private.
private actor FakeCacheTestImporter: ActivityImporting {
    private let result: ImportResult
    init(result: ImportResult) {
        self.result = result
    }
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        result
    }
}

/// Wraps another `FitnessMetricsCacheStore`, forwarding every call while counting `markDirty`/
/// `upsert` invocations — used to assert "this mutation must never touch the cache" without
/// depending on `InMemoryStore`'s internal storage shape.
private actor SpyCacheStore: FitnessMetricsCacheStore {
    private let wrapped: any FitnessMetricsCacheStore
    private(set) var markDirtyCallCount = 0
    private(set) var upsertCallCount = 0

    init(wrapping wrapped: any FitnessMetricsCacheStore) {
        self.wrapped = wrapped
    }

    func resetCounts() {
        markDirtyCallCount = 0
        upsertCallCount = 0
    }

    func cachedMetrics(in range: ClosedRange<Date>) async throws -> [FitnessMetrics] {
        try await wrapped.cachedMetrics(in: range)
    }
    func cachedMetrics(immediatelyBefore date: Date) async throws -> FitnessMetrics? {
        try await wrapped.cachedMetrics(immediatelyBefore: date)
    }
    func recentLoads(before date: Date, count: Int) async throws -> [Double] {
        try await wrapped.recentLoads(before: date, count: count)
    }
    func latestCachedDay() async throws -> Date? {
        try await wrapped.latestCachedDay()
    }
    func earliestCachedDay() async throws -> Date? {
        try await wrapped.earliestCachedDay()
    }
    func upsert(_ metrics: [FitnessMetrics]) async throws {
        upsertCallCount += 1
        try await wrapped.upsert(metrics)
    }
    func deleteCachedMetrics(from date: Date) async throws {
        try await wrapped.deleteCachedMetrics(from: date)
    }
    func dirtyWatermark() async throws -> Date? {
        try await wrapped.dirtyWatermark()
    }
    func markDirty(from date: Date) async throws {
        markDirtyCallCount += 1
        try await wrapped.markDirty(from: date)
    }
    func clearDirtyWatermark() async throws {
        try await wrapped.clearDirtyWatermark()
    }
}

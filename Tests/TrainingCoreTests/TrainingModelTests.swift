import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel", .serialized)
struct TrainingModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, stores)
    }

    private func steadyWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("load(in:) populates state from the stores")
    func loadPopulatesState() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))

        try await store.upsert([workout])
        try await store.upsert([plan])
        try await store.upsert([meso])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(13), asOf: day(3))

        #expect(model.workouts.map(\.id) == [workout.id])
        #expect(model.plans.map(\.id) == [plan.id])
        #expect(model.cycles.map(\.id) == [meso.id])
        #expect(!model.metrics.isEmpty)
    }

    @Test("load(in:) sets hasEverImportedActivities from the persisted anchor, independent of activities.isEmpty")
    func loadReflectsPersistedAnchorRegardlessOfLoadedActivities() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        // An activity outside the loaded range: activities.isEmpty will be true after load, but a
        // prior import having happened should still be reflected in hasEverImportedActivities.
        let outOfRange = Activity(source: .healthKit(UUID()), sport: .running, start: day(50), duration: 1800)
        try await store.upsert([outOfRange])
        try await store.saveImportAnchor(ImportAnchor(data: Data([9])))

        let model = TrainingModel(stores: stores, athlete: athlete)
        #expect(!model.hasEverImportedActivities)

        try await model.load(in: day(0)...day(10), asOf: day(3))

        #expect(model.activities.isEmpty)
        #expect(model.hasEverImportedActivities)
    }

    @Test("add(_ plan:) persists to the store and updates metrics")
    func addPlanPersistsAndRecomputes() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(0))
        #expect(model.metrics.allSatisfy { $0.load == 0 })

        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await model.add(plan, asOf: day(0))

        #expect(model.plans.map(\.id) == [plan.id])
        #expect(try await store.plan(id: plan.id) == plan)
        let planDayMetrics = model.metrics.first { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: day(5)) }
        #expect((planDayMetrics?.load ?? 0) > 0)
    }

    @Test("add(_ cycles:) persists to the store and updates local state")
    func addCyclesPersistsAndUpdates() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(13), asOf: day(0))
        #expect(model.cycles.isEmpty)

        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        try await model.add([meso], asOf: day(0))

        #expect(model.cycles.map(\.id) == [meso.id])
        #expect(try await store.cycle(id: meso.id) == meso)
    }

    @Test("recompute(asOf:) is deterministic for a fixed today")
    func recomputeIsDeterministic() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await store.upsert([workout])
        try await store.upsert([plan])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(3))
        let firstRun = model.metrics

        await model.recompute(asOf: day(3))
        let secondRun = model.metrics

        #expect(firstRun.map(\.load) == secondRun.map(\.load))
        #expect(firstRun.map(\.ctl) == secondRun.map(\.ctl))
    }

    @Test("add(_ plan:) reflects the addition even if load(in:) was never called")
    func addPlanWithoutPriorLoad() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        let model = TrainingModel(stores: stores, athlete: athlete)
        let plan = PlannedActivity(workoutID: workout.id, date: day(0))
        try await model.add(plan, asOf: day(0))

        #expect(model.plans.map(\.id) == [plan.id])
        #expect(try await store.plan(id: plan.id) == plan)
        #expect(model.metrics.contains { $0.load > 0 })
    }

    @Test("recompute(asOf:) pads metrics through the loaded range even with no activity/plan near its end")
    func recomputePadsThroughLoadedRangeWithoutCache() async throws {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        // No activities or plans anywhere -- DailyLoadSeries has nothing of its own to anchor the
        // far end of day(0)...day(10) with, so without padding the series would stop at `today`
        // (day(0)) and day(10) would simply be missing from `model.metrics`.
        try await model.load(in: day(0)...day(10), asOf: day(0))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let lastDay = try #require(model.metrics.map(\.day).max())
        #expect(calendar.isDate(lastDay, inSameDayAs: day(10)))
        #expect(model.metrics.last?.load == 0)
    }

    @Test("a failed load(in:) leaves the model unchanged rather than partially updated")
    func failedLoadLeavesModelUnchanged() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])

        var throwingStores = stores
        throwingStores.planStore = ThrowingPlanStore()
        let model = TrainingModel(stores: throwingStores, athlete: athlete)

        await #expect(throws: (any Error).self) {
            try await model.load(in: day(0)...day(1), asOf: day(0))
        }

        #expect(model.activities.isEmpty)
        #expect(model.metrics.isEmpty)
    }

    @Test("importActivities(from:) upserts, deletes, persists the anchor, and recomputes")
    func importActivitiesUpsertsAndPersistsAnchor() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let existing = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([existing])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(3))
        #expect(try await store.importAnchor() == nil)

        let imported = Activity(
            source: .healthKit(UUID()), sport: .cycling, start: day(2), duration: 3600,
            perceivedExertion: 5
        )
        let importer = FakeImporter(result: ImportResult(
            upserted: [imported],
            deletedSources: [existing.source],
            anchor: ImportAnchor(data: Data([1, 2, 3]))
        ))

        try await model.importActivities(from: importer, asOf: day(3))

        #expect(model.activities.map(\.id).sorted() == [imported.id].sorted())
        #expect(try await store.activity(id: existing.id) == nil)
        #expect(try await store.activity(id: imported.id) == imported)
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([1, 2, 3])))
        #expect(model.hasEverImportedActivities)
        #expect(await importer.receivedAnchor == nil)
        let importedDayMetrics = model.metrics.first { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: day(2)) }
        #expect((importedDayMetrics?.load ?? 0) > 0)
    }

    @Test("importActivities(from:) doesn't clear hasEverImportedActivities when an importer returns a nil anchor")
    func importActivitiesWithNilAnchorDoesNotClearHasEverImported() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        let firstImporter = FakeImporter(result: ImportResult(
            upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1]))
        ))
        try await model.importActivities(from: firstImporter, asOf: day(0))
        #expect(model.hasEverImportedActivities)

        // A second importer that doesn't support incremental import (a valid `ActivityImporting`
        // conformer per its own doc comment) returns a nil anchor -- the completed import this
        // represents must not read back as "never imported".
        let secondImporter = FakeImporter(result: ImportResult(upserted: [], deletedSources: [], anchor: nil))
        try await model.importActivities(from: secondImporter, asOf: day(0))

        #expect(try await store.importAnchor() == nil)
        #expect(model.hasEverImportedActivities)
    }

    @Test("importActivities(from:) passes the previously persisted anchor")
    func importActivitiesPassesPersistedAnchor() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let priorAnchor = ImportAnchor(data: Data([9, 9]))
        try await store.saveImportAnchor(priorAnchor)

        let model = TrainingModel(stores: stores, athlete: athlete)
        let importer = FakeImporter(result: ImportResult(upserted: [], deletedSources: [], anchor: nil))

        try await model.importActivities(from: importer, asOf: day(0))

        #expect(await importer.receivedAnchor == priorAnchor)
        #expect(try await store.importAnchor() == nil)
    }

    @Test("importActivities(from:) propagates a store failure without saving the anchor")
    func importActivitiesFailurePropagates() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        var throwingStores = stores
        throwingStores.activityStore = ThrowingActivityStore()
        let model = TrainingModel(stores: throwingStores, athlete: athlete)

        let imported = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        let importer = FakeImporter(result: ImportResult(
            upserted: [imported], deletedSources: [], anchor: ImportAnchor(data: Data([1]))
        ))

        await #expect(throws: (any Error).self) {
            try await model.importActivities(from: importer, asOf: day(0))
        }

        #expect(model.activities.isEmpty)
        #expect(try await store.importAnchor() == nil)
    }

    @Test("importActivities(from:) reflects the import even if load(in:) was never called")
    func importActivitiesWithoutPriorLoad() async throws {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        let imported = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800,
            perceivedExertion: 5
        )
        let importer = FakeImporter(result: ImportResult(upserted: [imported], deletedSources: [], anchor: nil))

        try await model.importActivities(from: importer, asOf: day(0))

        #expect(model.activities.map(\.id) == [imported.id])
        #expect(model.metrics.contains { $0.load > 0 })
    }

    @Test("resyncActivities(from:) clears the persisted anchor before importing, so the importer sees a full import")
    func resyncActivitiesClearsAnchorFirst() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        try await store.saveImportAnchor(ImportAnchor(data: Data([9, 9])))

        let model = TrainingModel(stores: stores, athlete: athlete)
        let imported = Activity(source: .healthKit(UUID()), sport: .hiking, start: day(0), duration: 1800)
        let importer = FakeImporter(result: ImportResult(
            upserted: [imported], deletedSources: [], anchor: ImportAnchor(data: Data([1]))
        ))

        try await model.resyncActivities(from: importer, asOf: day(0))

        #expect(await importer.receivedAnchor == nil)
        #expect(try await store.activity(id: imported.id) == imported)
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([1])))
    }

    @Test("resyncActivities(from:) replaces an existing record's stale Sport rather than duplicating it")
    func resyncActivitiesReplacesStaleRecordInPlace() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let source = ActivitySource.healthKit(UUID())
        let stale = Activity(source: source, sport: .other(Sport.otherLabel(rawValue: 52)), start: day(0), duration: 1800)
        try await store.upsert([stale])
        try await store.saveImportAnchor(ImportAnchor(data: Data([9, 9])))

        let model = TrainingModel(stores: stores, athlete: athlete)
        let corrected = Activity(id: stale.id, source: source, sport: .hiking, start: day(0), duration: 1800)
        let importer = FakeImporter(result: ImportResult(upserted: [corrected], deletedSources: [], anchor: nil))

        try await model.resyncActivities(from: importer, asOf: day(0))

        let all = try await store.activities(in: day(0)...day(0))
        #expect(all.map(\.id) == [stale.id])
        #expect(all.first?.sport == .hiking)
    }

    @Test("overlapping importActivities(from:) calls are serialized, not interleaved")
    func overlappingImportsAreSerialized() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        let firstImporter = GatedImporter(result: ImportResult(
            upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1]))
        ))
        async let firstImport: Void = model.importActivities(from: firstImporter, asOf: day(0))
        await firstImporter.waitUntilCalled()

        let secondImporter = FakeImporter(result: ImportResult(
            upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([2]))
        ))
        async let secondImport: Void = model.importActivities(from: secondImporter, asOf: day(0))

        // The second call's Task has already started running, but it must be queued behind the
        // first -- it shouldn't have reached its own importer call yet. This is not a timing
        // guess: with the queue broken, the second call would race ahead and call its importer
        // immediately regardless of how long this sleeps, so any nonzero sleep reliably catches
        // that regression.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await secondImporter.callCount == 0)

        await firstImporter.release()
        _ = try await (firstImport, secondImport)

        // The second call's importer received the first call's freshly-saved anchor, not the nil
        // anchor that was persisted when the second call started -- proof its anchor read only
        // happened after the first call's anchor save completed, which is exactly the window
        // MVP1-26 closes: before this fix, both calls could read the same stale anchor and act on
        // it concurrently.
        #expect(await secondImporter.receivedAnchor == ImportAnchor(data: Data([1])))
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([2])))
    }

    @Test("resyncActivities(from:) racing an in-flight importActivities(from:) is queued behind it")
    func resyncRacingImportIsQueued() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)

        let firstImporter = GatedImporter(result: ImportResult(
            upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1]))
        ))
        async let firstImport: Void = model.importActivities(from: firstImporter, asOf: day(0))
        await firstImporter.waitUntilCalled()

        let resyncImporter = FakeImporter(result: ImportResult(
            upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([2]))
        ))
        async let resync: Void = model.resyncActivities(from: resyncImporter, asOf: day(0))

        try await Task.sleep(for: .milliseconds(50))
        #expect(await resyncImporter.callCount == 0) // still queued behind the first import

        await firstImporter.release()
        _ = try await (firstImport, resync)

        // The resync's anchor-clear ran only after the first import's own anchor save -- had it
        // run immediately instead of being queued, the first import's later `saveImportAnchor`
        // would have silently undone the resync's clear, and the resync's importer would have seen
        // a non-nil anchor instead of the nil a full resync promises.
        #expect(await resyncImporter.receivedAnchor == nil)
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([2])))
    }

    @Test("resyncActivities(from:) propagates a failure clearing the anchor, without calling the importer")
    func resyncActivitiesAnchorClearFailurePropagates() async throws {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        var throwingStores = stores
        throwingStores.athleteStore = ThrowingAthleteStore()
        let model = TrainingModel(stores: throwingStores, athlete: athlete)

        let importer = FakeImporter(result: ImportResult(upserted: [], deletedSources: [], anchor: nil))

        await #expect(throws: (any Error).self) {
            try await model.resyncActivities(from: importer, asOf: day(0))
        }

        #expect(await importer.callCount == 0)
    }

    @Test("deduplicateActivities(asOf:) reloads activities and recomputes when duplicates are removed")
    func deduplicateActivitiesReloadsAndRecomputes() async throws {
        let athlete = AthleteProfile.fixture()
        let kept = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800,
            perceivedExertion: 5
        )
        let duplicate = Activity(
            source: .healthKit(UUID()), sport: .cycling, start: day(0), duration: 3600,
            perceivedExertion: 5
        )
        let fakeActivityStore = DeduplicatingActivityStore(activities: [kept, duplicate], toRemove: [duplicate])
        let otherStores = InMemoryStore()
        let stores = StoreSet(
            activityStore: fakeActivityStore, planStore: otherStores, workoutStore: otherStores,
            cycleStore: otherStores, athleteStore: otherStores
        )

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(0), asOf: day(0))
        #expect(model.activities.map(\.id).sorted() == [kept.id, duplicate.id].sorted())

        try await model.deduplicateActivities(asOf: day(0))

        #expect(model.activities.map(\.id) == [kept.id])
        let dayMetrics = model.metrics.first { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: day(0)) }
        // The duplicate's cycling load is gone from the day's total -- what's left is only the
        // kept running activity's own load, not the inflated sum of both.
        #expect((dayMetrics?.load ?? 0) > 0)
        #expect(try await fakeActivityStore.activity(id: duplicate.id) == nil)
    }

    @Test("deduplicateActivities(asOf:) racing an in-flight importActivities(from:) is queued behind it")
    func deduplicateRacingImportIsQueued() async throws {
        let athlete = AthleteProfile.fixture()
        let gatedStore = GatedActivityStore()
        let otherStores = InMemoryStore()
        let stores = StoreSet(
            activityStore: gatedStore, planStore: otherStores, workoutStore: otherStores,
            cycleStore: otherStores, athleteStore: otherStores
        )
        let model = TrainingModel(stores: stores, athlete: athlete)

        async let dedupe: Void = try model.deduplicateActivities(asOf: day(0))
        await gatedStore.waitUntilCalled()

        let importer = FakeImporter(result: ImportResult(upserted: [], deletedSources: [], anchor: nil))
        async let secondImport: Void = model.importActivities(from: importer, asOf: day(0))

        // The import's Task has already started running, but it must be queued behind the
        // dedupe -- it shouldn't have reached its own importer call yet. Not a timing guess: with
        // the queue broken (e.g. deduplicateActivities accidentally using a queue of its own
        // instead of sharing pendingImport), the import would race ahead regardless of how long
        // this sleeps.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await importer.callCount == 0)

        await gatedStore.release()
        _ = try await (dedupe, secondImport)

        #expect(await importer.callCount == 1)
    }
}

/// Reports a fixed set of "removed" activities from `deduplicateActivities()` and removes them
/// from its own backing set, so `activities(in:)` reflects the removal afterward — used to test
/// `TrainingModel.deduplicateActivities(asOf:)` since `InMemoryStore`'s own `upsert` dedup makes
/// it impossible to get real duplicates into the store to begin with (see `InMemoryStoreTests`'
/// and `SwiftDataStoreTests`' own `deduplicateActivities` coverage for the store-level behavior).
private actor DeduplicatingActivityStore: ActivityStore {
    private var activitiesByID: [UUID: Activity]
    private let toRemove: [Activity]

    init(activities: [Activity], toRemove: [Activity]) {
        activitiesByID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        self.toRemove = toRemove
    }

    func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        activitiesByID.values.filter { range.contains($0.start) }
    }
    func upsert(_ activities: [Activity]) async throws {
        for activity in activities { activitiesByID[activity.id] = activity }
    }
    func activity(source: ActivitySource) async throws -> Activity? {
        activitiesByID.values.first { $0.source == source }
    }
    func activity(id: UUID) async throws -> Activity? { activitiesByID[id] }
    func deleteActivity(source: ActivitySource) async throws {
        if let id = activitiesByID.values.first(where: { $0.source == source })?.id {
            activitiesByID.removeValue(forKey: id)
        }
    }
    func deduplicateActivities() async throws -> [Activity] {
        for activity in toRemove { activitiesByID.removeValue(forKey: activity.id) }
        return toRemove
    }
}

private struct ThrowingPlanStore: PlanStore {
    struct Boom: Error {}
    func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] { throw Boom() }
    func upsert(_ plans: [PlannedActivity]) async throws {}
    func plan(id: UUID) async throws -> PlannedActivity? { nil }
    func deletePlan(id: UUID) async throws {}
}

/// Throws on `upsert` (used to test `importActivities(from:)`'s failure path) but otherwise behaves
/// like an always-empty store, so `activities(in:)` reads after the throw still succeed.
private struct ThrowingActivityStore: ActivityStore {
    struct Boom: Error {}
    func activities(in range: ClosedRange<Date>) async throws -> [Activity] { [] }
    func upsert(_ activities: [Activity]) async throws { throw Boom() }
    func activity(source: ActivitySource) async throws -> Activity? { nil }
    func activity(id: UUID) async throws -> Activity? { nil }
    func deleteActivity(source: ActivitySource) async throws {}
    func deduplicateActivities() async throws -> [Activity] { [] }
}

/// Throws on `saveImportAnchor` (used to test `resyncActivities(from:)`'s anchor-clear failure
/// path) but otherwise behaves like an always-empty store.
private struct ThrowingAthleteStore: AthleteStore {
    struct Boom: Error {}
    func athleteProfile() async throws -> AthleteProfile? { nil }
    func save(_ profile: AthleteProfile) async throws {}
    func importAnchor() async throws -> ImportAnchor? { nil }
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws { throw Boom() }
}

/// An actor, not a plain class with `@unchecked Sendable`, so `receivedAnchor` is genuinely
/// data-race-safe even if a future test calls `importActivities(since:)` concurrently.
private actor FakeImporter: ActivityImporting {
    private let result: ImportResult
    private(set) var receivedAnchor: ImportAnchor?
    private(set) var callCount = 0

    init(result: ImportResult) {
        self.result = result
    }

    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        receivedAnchor = anchor
        callCount += 1
        return result
    }
}

/// An `ActivityImporting` that suspends inside `importActivities(since:)` until ``release()`` is
/// called, so a test can deterministically hold one `TrainingModel.importActivities(from:)`/
/// `resyncActivities(from:)` call open mid-flight and observe whether a second, overlapping call
/// is allowed to race ahead of it or is queued behind it instead.
private actor GatedImporter: ActivityImporting {
    private let result: ImportResult
    private(set) var callCount = 0
    private(set) var receivedAnchor: ImportAnchor?
    private var continuation: CheckedContinuation<Void, Never>?
    /// Resolved once `importActivities(since:)` has actually been entered, so callers can wait
    /// past the "the async let Task exists but hasn't run yet" gap instead of guessing with a
    /// sleep or a spin loop.
    private var calledContinuation: CheckedContinuation<Void, Never>?

    init(result: ImportResult) {
        self.result = result
    }

    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        receivedAnchor = anchor
        callCount += 1
        calledContinuation?.resume()
        calledContinuation = nil
        await withCheckedContinuation { continuation = $0 }
        return result
    }

    func waitUntilCalled() async {
        if callCount > 0 { return }
        await withCheckedContinuation { calledContinuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

/// An `ActivityStore` whose `deduplicateActivities()` blocks until released — used to prove
/// `TrainingModel.deduplicateActivities(asOf:)` shares `pendingImport`'s queue with
/// `importActivities(from:)`/`resyncActivities(from:)`, the same way `GatedImporter` proves it for
/// two imports racing each other. Every other method is a minimal passthrough; this fake exists
/// only to gate the one call this test needs to observe.
private actor GatedActivityStore: ActivityStore {
    private(set) var deduplicateCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var calledContinuation: CheckedContinuation<Void, Never>?

    func activities(in range: ClosedRange<Date>) async throws -> [Activity] { [] }
    func upsert(_ activities: [Activity]) async throws {}
    func activity(source: ActivitySource) async throws -> Activity? { nil }
    func activity(id: UUID) async throws -> Activity? { nil }
    func deleteActivity(source: ActivitySource) async throws {}

    func deduplicateActivities() async throws -> [Activity] {
        deduplicateCallCount += 1
        calledContinuation?.resume()
        calledContinuation = nil
        await withCheckedContinuation { continuation = $0 }
        return []
    }

    func waitUntilCalled() async {
        if deduplicateCallCount > 0 { return }
        await withCheckedContinuation { calledContinuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

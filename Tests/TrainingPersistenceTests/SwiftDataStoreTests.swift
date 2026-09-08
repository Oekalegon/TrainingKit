import Foundation
import SwiftData
import Testing
@testable import TrainingPersistence
import TrainingCore

@Suite("SwiftDataStore")
struct SwiftDataStoreTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// A fresh in-memory, non-CloudKit store per test — mirrors `InMemoryStoreTests`' one-store-
    /// per-test isolation, but backed by a real `ModelContainer`/`ModelContext` so this exercises
    /// actual SwiftData behavior (predicates, save semantics) rather than a hand-rolled dictionary.
    private func makeStore() throws -> SwiftDataStore {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        return SwiftDataStore(modelContainer: container)
    }

    @Test("ActivityStore upsert/fetch round-trips and filters by date range")
    func activityStoreRoundTrip() async throws {
        let store = try makeStore()
        let inRange = Activity(source: .manual, sport: .running, start: day(5), duration: 1800)
        let outOfRange = Activity(source: .manual, sport: .running, start: day(50), duration: 1800)

        try await store.upsert([inRange, outOfRange])

        let fetched = try await store.activities(in: day(0)...day(10))
        #expect(fetched.map(\.id) == [inRange.id])
        #expect(try await store.activity(id: outOfRange.id) == outOfRange)
    }

    @Test("ActivityStore upsert replaces an existing record matched by id, rather than duplicating it")
    func activityStoreUpsertReplacesExisting() async throws {
        let store = try makeStore()
        let original = Activity(id: UUID(), source: .manual, sport: .running, start: day(0), duration: 1800)
        try await store.upsert([original])

        var updated = original
        updated.duration = 3600
        try await store.upsert([updated])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(all.count == 1)
        #expect(all.first?.duration == 3600)
    }

    @Test("ActivityStore upsert doesn't duplicate when two new activities share an id in one batch")
    func activityStoreUpsertDedupesWithinOneBatch() async throws {
        let store = try makeStore()
        let id = UUID()
        let first = Activity(id: id, source: .manual, sport: .running, start: day(0), duration: 1800)
        var second = first
        second.duration = 3600

        // Neither `first` nor `second` exists in the store yet -- this exercises the in-memory
        // lookup `upsert` builds for the whole batch, not the id == existing-record path the
        // "replaces an existing record" test above covers.
        try await store.upsert([first, second])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(all.count == 1)
        #expect(all.first?.duration == 3600)
    }

    @Test("ActivityStore dedupes on source")
    func activityStoreDedupeOnSource() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)

        try await store.upsert([activity])

        #expect(try await store.activity(source: source) == activity)
        #expect(try await store.activity(source: .manual) == nil)
    }

    @Test("ActivityStore dedupes .fitFile sources that differ only in URL representation")
    func activityStoreDedupeOnFitFileURLNormalization() async throws {
        let store = try makeStore()
        let canonical = URL(fileURLWithPath: "/tmp/imports/ride.fit")
        let equivalent = URL(fileURLWithPath: "/tmp/imports/../imports/ride.fit")
        let activity = Activity(source: .fitFile(canonical), sport: .cycling, start: day(0), duration: 3600)

        try await store.upsert([activity])

        // Same file, spelled differently -- must resolve to the same stored record.
        #expect(try await store.activity(source: .fitFile(equivalent)) == activity)
    }

    @Test("ActivityStore upsert replaces a stale record when a new activity reuses its source under a different id")
    func activityStoreUpsertDedupesOnSourceAcrossDifferentIDs() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let stale = Activity(source: source, sport: .running, start: day(0), duration: 1800)
        try await store.upsert([stale])

        // Same source, a different id -- the shape the pre-MVP1-26 TOCTOU race could produce: two
        // overlapping imports both look up `source`, both find nothing yet, and both build a fresh
        // id for the same workout. `upsert` needs to collapse this to one row on its own, as
        // defense-in-depth alongside that race's fix.
        let duplicate = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([duplicate])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(all.map(\.id) == [duplicate.id])
        #expect(try await store.activity(id: stale.id) == nil)
        #expect(try await store.activity(source: source) == duplicate)
    }

    @Test("ActivityStore deduplicateActivities removes extras sharing a source, keeping exactly one")
    func activityStoreDeduplicateActivitiesRemovesDuplicates() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let manual = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        try await store.upsert([manual])

        // Simulates duplicates left over from before upsert's defense-in-depth dedup existed:
        // seeded directly via a raw ModelContext against the same container, bypassing upsert
        // (which would never let this state occur today) the way pre-fix persisted/CloudKit-synced
        // data actually does.
        let context = ModelContext(store.modelContainer)
        let first = try ActivityRecord(
            activity: Activity(source: source, sport: .running, start: day(0), duration: 1800)
        )
        let second = try ActivityRecord(
            activity: Activity(source: source, sport: .cycling, start: day(1), duration: 3600)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let removed = try await store.deduplicateActivities()

        #expect(removed.count == 1)
        // Manual activities are untouched -- only the non-manual duplicate group is deduped.
        let remaining = try await store.activities(in: day(0)...day(2))
        #expect(remaining.count == 2)
        #expect(remaining.contains { $0.source == .manual })
        #expect(remaining.contains { $0.source == source })
    }

    @Test("ActivityStore deduplicateActivities is a no-op when there are no duplicates")
    func activityStoreDeduplicateActivitiesNoOp() async throws {
        let store = try makeStore()
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])

        let removed = try await store.deduplicateActivities()

        #expect(removed.isEmpty)
        #expect(try await store.activity(id: activity.id) == activity)
    }

    @Test("ActivityStore upsert dedupes two new activities that share a source within one batch")
    func activityStoreUpsertDedupesOnSourceWithinOneBatch() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let first = Activity(source: source, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)

        // Neither exists in the store yet -- exercises the batch-local index, not the
        // already-stored path the test above covers.
        try await store.upsert([first, second])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(all.map(\.id) == [second.id])
    }

    @Test("ActivityStore upsert never dedupes .manual activities against each other")
    func activityStoreUpsertDoesNotDedupeManualActivities() async throws {
        let store = try makeStore()
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0), duration: 3600)

        // `.manual` has no natural key -- two distinct manually-entered activities must both
        // survive, not collapse into one just because they share `source == .manual`.
        try await store.upsert([first, second])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("ActivityStore deleteActivity removes by source, no-ops if not found")
    func activityStoreDeleteActivity() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])

        try await store.deleteActivity(source: .healthKit(UUID())) // unrelated source: no-op
        #expect(try await store.activity(source: source) == activity)

        try await store.deleteActivity(source: source)
        #expect(try await store.activity(source: source) == nil)
        #expect(try await store.activity(id: activity.id) == nil)
    }

    @Test("ActivityStore deleteAllActivities removes every activity and reports how many")
    func activityStoreDeleteAllActivities() async throws {
        let store = try makeStore()
        let activities = (0..<5).map { Activity(source: .healthKit(UUID()), sport: .running, start: day($0), duration: 1800) }
        try await store.upsert(activities)

        let deletedCount = try await store.deleteAllActivities()

        #expect(deletedCount == 5)
        #expect(try await store.activities(in: day(0)...day(4)).isEmpty)
    }

    @Test("AthleteStore import anchor round-trips and clears to nil")
    func athleteStoreImportAnchor() async throws {
        let store = try makeStore()
        #expect(try await store.importAnchor() == nil)

        let anchor = ImportAnchor(data: Data([1, 2, 3]))
        try await store.saveImportAnchor(anchor)
        #expect(try await store.importAnchor() == anchor)

        try await store.saveImportAnchor(nil)
        #expect(try await store.importAnchor() == nil)
    }

    @Test("AthleteStore save/fetch")
    func athleteStoreSaveFetch() async throws {
        let store = try makeStore()
        #expect(try await store.athleteProfile() == nil)

        let profile = AthleteProfile.fixture()
        try await store.save(profile)

        #expect(try await store.athleteProfile() == profile)
    }

    @Test("AthleteStore profile and import anchor are independent: saving one doesn't clobber the other")
    func athleteStoreProfileAndAnchorAreIndependent() async throws {
        let store = try makeStore()

        try await store.saveImportAnchor(ImportAnchor(data: Data([9])))
        #expect(try await store.athleteProfile() == nil)

        let profile = AthleteProfile.fixture()
        try await store.save(profile)
        #expect(try await store.importAnchor() == ImportAnchor(data: Data([9])))
        #expect(try await store.athleteProfile() == profile)
    }

    @Test("PlanStore upsert/fetch/delete")
    func planStoreCRUD() async throws {
        let store = try makeStore()
        let plan = PlannedActivity(workoutID: UUID(), date: day(3))

        try await store.upsert([plan])
        #expect(try await store.plan(id: plan.id) == plan)
        #expect(try await store.plans(in: day(0)...day(10)).map(\.id) == [plan.id])

        try await store.deletePlan(id: plan.id)
        #expect(try await store.plan(id: plan.id) == nil)
    }

    @Test("WorkoutLibraryStore upsert/fetch/delete")
    func workoutLibraryStoreCRUD() async throws {
        let store = try makeStore()
        let workout = StructuredWorkout(name: "Easy run", sport: .running, blocks: [])

        try await store.upsert([workout])
        #expect(try await store.workout(id: workout.id) == workout)
        #expect(try await store.workouts().map(\.id) == [workout.id])

        try await store.deleteWorkout(id: workout.id)
        #expect(try await store.workout(id: workout.id) == nil)
    }

    @Test("CycleStore accepts a valid parent + non-overlapping children in one batch")
    func cycleStoreAcceptsValidNesting() async throws {
        let store = try makeStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(27))
        let microA = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)
        let microB = TrainingCycle(level: .micro, phase: .recovery, name: "Week 2", dateRange: day(7)...day(13), parentID: meso.id)

        try await store.upsert([meso, microA, microB])

        let stored = try await store.cycles(in: day(0)...day(27))
        #expect(Set(stored.map(\.id)) == Set([meso.id, microA.id, microB.id]))
    }

    @Test("CycleStore accepts a parent + children in one batch regardless of array order")
    func cycleStoreAcceptsValidNestingRegardlessOfOrder() async throws {
        let store = try makeStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        let micro = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)

        // The child is listed BEFORE its parent — this must resolve identically to parent-first.
        try await store.upsert([micro, meso])

        #expect(try await store.cycle(id: meso.id) == meso)
        #expect(try await store.cycle(id: micro.id) == micro)
    }

    @Test("CycleStore rejects a child outside its parent's range")
    func cycleStoreRejectsOutOfRangeChild() async throws {
        let store = try makeStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        try await store.upsert([meso])

        let overhangingChild = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(7)...day(20), parentID: meso.id)

        await #expect(throws: CycleStoreError.childOutsideParentRange(child: overhangingChild.id, parent: meso.id)) {
            try await store.upsert([overhangingChild])
        }
    }

    @Test("CycleStore rejects overlapping siblings")
    func cycleStoreRejectsOverlappingSiblings() async throws {
        let store = try makeStore()
        let existing = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        try await store.upsert([existing])

        let overlapping = TrainingCycle(level: .micro, phase: .build, name: "Week 1b", dateRange: day(5)...day(11))

        await #expect(throws: CycleStoreError.overlappingSiblings(overlapping.id, existing.id)) {
            try await store.upsert([overlapping])
        }
    }

    @Test("CycleStore rejects a parentID that doesn't resolve")
    func cycleStoreRejectsMissingParent() async throws {
        let store = try makeStore()
        let orphan = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: UUID())

        await #expect(throws: CycleStoreError.self) {
            try await store.upsert([orphan])
        }
    }

    @Test("CycleStore delete removes a cycle")
    func cycleStoreDelete() async throws {
        let store = try makeStore()
        let cycle = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        try await store.upsert([cycle])

        try await store.deleteCycle(id: cycle.id)

        #expect(try await store.cycle(id: cycle.id) == nil)
    }

    @Test("CycleStore rejects deleting a cycle that still has children")
    func cycleStoreRejectsDeletingCycleWithChildren() async throws {
        let store = try makeStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        let micro = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)
        try await store.upsert([meso, micro])

        await #expect(throws: CycleStoreError.hasChildren(meso.id)) {
            try await store.deleteCycle(id: meso.id)
        }

        // Deleting the child first, then the parent, succeeds.
        try await store.deleteCycle(id: micro.id)
        try await store.deleteCycle(id: meso.id)
        #expect(try await store.cycle(id: meso.id) == nil)
    }

    // MARK: FitnessMetricsCacheStore

    private func metrics(day: Date, load: Double = 50) -> FitnessMetrics {
        FitnessMetrics(
            day: day, load: load, ctl: load, atl: load, tsb: 0,
            monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
        )
    }

    @Test("FitnessMetricsCacheStore upsert/fetch round-trips and replaces by day rather than duplicating")
    func fitnessMetricsCacheUpsertRoundTrips() async throws {
        let store = try makeStore()
        try await store.upsert([metrics(day: day(0), load: 10), metrics(day: day(1), load: 20)])

        let fetched = try await store.cachedMetrics(in: day(0)...day(1))
        #expect(Set(fetched.map(\.day)) == Set([day(0), day(1)]))

        try await store.upsert([metrics(day: day(0), load: 999)])
        let refetched = try await store.cachedMetrics(in: day(0)...day(0))
        #expect(refetched.count == 1)
        #expect(refetched.first?.load == 999)
    }

    @Test("FitnessMetricsCacheStore's monotony/strain (which can be NaN) round-trips through persistence")
    func fitnessMetricsCacheRoundTripsNaN() async throws {
        let store = try makeStore()
        try await store.upsert([metrics(day: day(0))]) // .nan monotony/strain

        let fetched = try await store.cachedMetrics(in: day(0)...day(0))
        #expect(fetched.first?.monotony.isNaN == true)
        #expect(fetched.first?.strain.isNaN == true)
    }

    @Test("FitnessMetricsCacheStore.deleteCachedMetrics(from:) removes every row with day >= date")
    func fitnessMetricsCacheDeleteFromBoundary() async throws {
        let store = try makeStore()
        try await store.upsert([metrics(day: day(0)), metrics(day: day(1)), metrics(day: day(2))])

        try await store.deleteCachedMetrics(from: day(1))

        let remaining = try await store.cachedMetrics(in: day(0)...day(2))
        #expect(remaining.map(\.day) == [day(0)])
    }

    @Test("FitnessMetricsCacheStore dirty watermark is a fetch-or-create singleton, mirroring AthleteStore")
    func fitnessMetricsCacheWatermarkSingleton() async throws {
        let store = try makeStore()
        #expect(try await store.dirtyWatermark() == nil)

        try await store.markDirty(from: day(5))
        #expect(try await store.dirtyWatermark() == day(5))

        try await store.markDirty(from: day(10)) // later — must not raise the watermark
        #expect(try await store.dirtyWatermark() == day(5))

        try await store.clearDirtyWatermark()
        #expect(try await store.dirtyWatermark() == nil)
    }
}

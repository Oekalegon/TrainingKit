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

    @Test("ActivityStore dedupes on source")
    func activityStoreDedupeOnSource() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)

        try await store.upsert([activity])

        #expect(try await store.activity(source: source) == activity)
        #expect(try await store.activity(source: .manual) == nil)
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
}

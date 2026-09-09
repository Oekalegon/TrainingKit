import Foundation
import Testing
@testable import TrainingCore

@Suite("InMemoryStore")
struct InMemoryStoreTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("ActivityStore upsert/fetch round-trips and filters by date range")
    func activityStoreRoundTrip() async throws {
        let store = InMemoryStore()
        let inRange = Activity(source: .manual, sport: .running, start: day(5), duration: 1800)
        let outOfRange = Activity(source: .manual, sport: .running, start: day(50), duration: 1800)

        try await store.upsert([inRange, outOfRange])

        let fetched = try await store.activities(in: day(0)...day(10))
        #expect(fetched.map(\.id) == [inRange.id])
        #expect(try await store.activity(id: outOfRange.id) == outOfRange)
    }

    @Test("ActivityStore dedupes on source")
    func activityStoreDedupeOnSource() async throws {
        let store = InMemoryStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)

        try await store.upsert([activity])

        #expect(try await store.activity(source: source) == activity)
        #expect(try await store.activity(source: .manual) == nil)
    }

    @Test("ActivityStore upsert replaces a stale record when a new activity reuses its source under a different id")
    func activityStoreUpsertDedupesOnSourceAcrossDifferentIDs() async throws {
        let store = InMemoryStore()
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

    @Test("ActivityStore upsert dedupes two new activities that share a source within one batch")
    func activityStoreUpsertDedupesOnSourceWithinOneBatch() async throws {
        let store = InMemoryStore()
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
        let store = InMemoryStore()
        let first = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .manual, sport: .cycling, start: day(0), duration: 3600)

        // `.manual` has no natural key -- two distinct manually-entered activities must both
        // survive, not collapse into one just because they share `source == .manual`.
        try await store.upsert([first, second])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("ActivityStore upsert never dedupes .testing activities against each other")
    func activityStoreUpsertDoesNotDedupeTestingActivities() async throws {
        let store = InMemoryStore()
        let first = Activity(source: .testing, sport: .running, start: day(0), duration: 1800)
        let second = Activity(source: .testing, sport: .cycling, start: day(0), duration: 3600)

        // `.testing` has no natural key, same as `.manual` -- two distinct activities seeded for
        // testing the app must both survive, not collapse into one just because they share
        // `source == .testing`.
        try await store.upsert([first, second])

        let all = try await store.activities(in: day(0)...day(0))
        #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("ActivityStore deleteActivity removes by source, no-ops if not found")
    func activityStoreDeleteActivity() async throws {
        let store = InMemoryStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])

        try await store.deleteActivity(source: .healthKit(UUID())) // unrelated source: no-op
        #expect(try await store.activity(source: source) == activity)

        try await store.deleteActivity(source: source)
        #expect(try await store.activity(source: source) == nil)
        #expect(try await store.activity(id: activity.id) == nil)
    }

    @Test("ActivityStore deduplicateActivities is a no-op when there are no duplicates")
    func activityStoreDeduplicateActivitiesNoOp() async throws {
        // InMemoryStore's own upsert already prevents two activities from ever sharing a source
        // (see the dedupe tests above), so there's no way to get it into a duplicated state via
        // its public API — this only exercises the empty-input/nothing-to-do path. The meaningful
        // removal behavior is covered against SwiftDataStore, where duplicates can be seeded
        // directly via a raw ModelContext, bypassing upsert's dedup the way pre-fix data would
        // have.
        let store = InMemoryStore()
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])

        let removed = try await store.deduplicateActivities()

        #expect(removed.isEmpty)
        #expect(try await store.activity(id: activity.id) == activity)
    }

    @Test("AthleteStore import anchor round-trips and clears to nil")
    func athleteStoreImportAnchor() async throws {
        let store = InMemoryStore()
        #expect(try await store.importAnchor() == nil)

        let anchor = ImportAnchor(data: Data([1, 2, 3]))
        try await store.saveImportAnchor(anchor)
        #expect(try await store.importAnchor() == anchor)

        try await store.saveImportAnchor(nil)
        #expect(try await store.importAnchor() == nil)
    }

    @Test("PlanStore upsert/fetch/delete")
    func planStoreCRUD() async throws {
        let store = InMemoryStore()
        let plan = PlannedActivity(workoutID: UUID(), date: day(3))

        try await store.upsert([plan])
        #expect(try await store.plan(id: plan.id) == plan)
        #expect(try await store.plans(in: day(0)...day(10)).map(\.id) == [plan.id])

        try await store.deletePlan(id: plan.id)
        #expect(try await store.plan(id: plan.id) == nil)
    }

    @Test("WorkoutLibraryStore upsert/fetch/delete")
    func workoutLibraryStoreCRUD() async throws {
        let store = InMemoryStore()
        let workout = StructuredWorkout(name: "Easy run", sport: .running, blocks: [])

        try await store.upsert([workout])
        #expect(try await store.workout(id: workout.id) == workout)
        #expect(try await store.workouts().map(\.id) == [workout.id])

        try await store.deleteWorkout(id: workout.id)
        #expect(try await store.workout(id: workout.id) == nil)
    }

    @Test("AthleteStore save/fetch")
    func athleteStoreSaveFetch() async throws {
        let store = InMemoryStore()
        #expect(try await store.athleteProfile() == nil)

        let profile = AthleteProfile.fixture()
        try await store.save(profile)

        #expect(try await store.athleteProfile() == profile)
    }

    @Test("CycleStore accepts a valid parent + non-overlapping children in one batch")
    func cycleStoreAcceptsValidNesting() async throws {
        let store = InMemoryStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(27))
        let microA = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)
        let microB = TrainingCycle(level: .micro, phase: .recovery, name: "Week 2", dateRange: day(7)...day(13), parentID: meso.id)

        try await store.upsert([meso, microA, microB])

        let stored = try await store.cycles(in: day(0)...day(27))
        #expect(Set(stored.map(\.id)) == Set([meso.id, microA.id, microB.id]))
    }

    @Test("CycleStore accepts a parent + children in one batch regardless of array order")
    func cycleStoreAcceptsValidNestingRegardlessOfOrder() async throws {
        let store = InMemoryStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        let micro = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)

        // The child is listed BEFORE its parent — this must resolve identically to parent-first.
        try await store.upsert([micro, meso])

        #expect(try await store.cycle(id: meso.id) == meso)
        #expect(try await store.cycle(id: micro.id) == micro)
    }

    @Test("CycleStore rejects a child outside its parent's range")
    func cycleStoreRejectsOutOfRangeChild() async throws {
        let store = InMemoryStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        try await store.upsert([meso])

        let overhangingChild = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(7)...day(20), parentID: meso.id)

        await #expect(throws: CycleStoreError.childOutsideParentRange(child: overhangingChild.id, parent: meso.id)) {
            try await store.upsert([overhangingChild])
        }
    }

    @Test("CycleStore rejects overlapping siblings")
    func cycleStoreRejectsOverlappingSiblings() async throws {
        let store = InMemoryStore()
        let existing = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        try await store.upsert([existing])

        let overlapping = TrainingCycle(level: .micro, phase: .build, name: "Week 1b", dateRange: day(5)...day(11))

        await #expect(throws: CycleStoreError.overlappingSiblings(overlapping.id, existing.id)) {
            try await store.upsert([overlapping])
        }
    }

    @Test("CycleStore lets a cycle update its own dateRange in place without colliding with its own prior version")
    func cycleStoreAllowsSelfUpdateOfDateRange() async throws {
        let store = InMemoryStore()
        var week1 = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        let week2 = TrainingCycle(level: .micro, phase: .build, name: "Week 2", dateRange: day(7)...day(13))
        try await store.upsert([week1, week2])

        // Shrinking week1 to end a day earlier must not be rejected as "overlapping" against the
        // stored version of itself — `CycleNestingValidator` overlays the incoming batch onto
        // `existing` before checking siblings specifically so a cycle never collides with its own
        // prior state.
        week1.dateRange = day(0)...day(5)
        try await store.upsert([week1])

        let updated = try await store.cycle(id: week1.id)
        #expect(updated?.dateRange == day(0)...day(5))
    }

    @Test("CycleStore still rejects a self-update that would newly overlap a sibling")
    func cycleStoreRejectsSelfUpdateThatNewlyOverlaps() async throws {
        let store = InMemoryStore()
        var week1 = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        let week2 = TrainingCycle(level: .micro, phase: .build, name: "Week 2", dateRange: day(7)...day(13))
        try await store.upsert([week1, week2])

        week1.dateRange = day(0)...day(8) // now overlaps week2's day(7)...day(13)

        await #expect(throws: CycleStoreError.overlappingSiblings(week1.id, week2.id)) {
            try await store.upsert([week1])
        }
    }

    @Test("CycleStore rejects a self-update that would grow a child outside its own parent's range")
    func cycleStoreRejectsSelfUpdateThatGrowsOutsideParentRange() async throws {
        let store = InMemoryStore()
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        var micro = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: meso.id)
        try await store.upsert([meso, micro])

        // Widening the child past its (unchanged) parent's upper bound must still be rejected on a
        // self-update, exactly as it would be for a brand-new out-of-range child — the parent-range
        // check isn't only exercised on insert.
        micro.dateRange = day(0)...day(20)

        await #expect(throws: CycleStoreError.childOutsideParentRange(child: micro.id, parent: meso.id)) {
            try await store.upsert([micro])
        }
    }

    @Test("CycleStore rejects a parentID that doesn't resolve")
    func cycleStoreRejectsMissingParent() async throws {
        let store = InMemoryStore()
        let orphan = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6), parentID: UUID())

        await #expect(throws: CycleStoreError.self) {
            try await store.upsert([orphan])
        }
    }

    @Test("CycleStore delete removes a cycle")
    func cycleStoreDelete() async throws {
        let store = InMemoryStore()
        let cycle = TrainingCycle(level: .micro, phase: .build, name: "Week 1", dateRange: day(0)...day(6))
        try await store.upsert([cycle])

        try await store.deleteCycle(id: cycle.id)

        #expect(try await store.cycle(id: cycle.id) == nil)
    }

    @Test("CycleStore rejects deleting a cycle that still has children")
    func cycleStoreRejectsDeletingCycleWithChildren() async throws {
        let store = InMemoryStore()
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

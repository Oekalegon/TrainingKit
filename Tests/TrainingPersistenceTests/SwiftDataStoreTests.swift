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
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
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

    @Test("a calendar placeholder keeps its imported load and flag, in the list item too (MVP2-107)")
    func calendarPlaceholderRoundTrip() async throws {
        let store = try makeStore()
        let placeholder = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(1), duration: 1800,
            importedLoad: 72, isCalendarImport: true
        )
        try await store.upsert([placeholder])

        #expect(try await store.activity(id: placeholder.id) == placeholder)
        let item = try #require(try await store.activityListItems(in: day(0)...day(2)).first)
        #expect(item.isCalendarImport)
    }

    @Test("an activity's venue round-trips, in the list item too")
    func venueRoundTrip() async throws {
        let store = try makeStore()
        let activity = Activity(source: .manual, sport: .running, venue: .outdoor(.trail), start: day(1), duration: 1800)
        try await store.upsert([activity])

        #expect(try await store.activity(id: activity.id)?.venue == .outdoor(.trail))
        let item = try #require(try await store.activityListItems(in: day(0)...day(2)).first)
        #expect(item.venue == .outdoor(.trail))
    }

    @Test("an edited sport and venue round-trips, and a payload without the edit flag decodes as unedited")
    func editedSportRoundTrip() async throws {
        let store = try makeStore()
        let activity = Activity(
            source: .manual, sport: .hiking, venue: .outdoor(.trail), start: day(1), duration: 1800, isSportEdited: true
        )
        try await store.upsert([activity])
        #expect(try await store.activity(id: activity.id) == activity)

        let record = try ActivityRecord(activity: activity)
        var json = try #require(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        json["isSportEdited"] = nil
        record.payload = try JSONSerialization.data(withJSONObject: json)
        #expect(try record.toActivity().isSportEdited == false)
    }

    @Test("a payload saved with the old outdoorRunning sport lists as running outdoors")
    func legacyVenueListItem() throws {
        let activity = Activity(source: .manual, sport: .running, start: day(1), duration: 1800)
        let record = try ActivityRecord(activity: activity)
        var json = try #require(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        json["sport"] = ["outdoorRunning": [String: Any]()]
        json["venue"] = nil
        record.payload = try JSONSerialization.data(withJSONObject: json)

        let item = try record.toListItem()
        #expect(item.sport == .running)
        #expect(item.venue == .outdoor(nil))
        #expect(try record.toActivity().venue == .outdoor(nil))
    }

    @Test("ActivityStore activityListItems matches activities(in:) without the samples, joins included (MVP2-129)")
    func activityStoreSummaries() async throws {
        let store = try makeStore()
        let planID = UUID()
        let hr = (0..<50).map { HeartRateSample(time: day(0).addingTimeInterval(Double($0)), bpm: 140) }
        let run = Activity(
            source: .manual, sport: .running, start: day(1), duration: 1800, distanceMeters: 5000,
            heartRate: hr, linkedPlanID: planID
        )
        let first = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(2), duration: 900)
        let second = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(2).addingTimeInterval(1000), duration: 900)
        let outOfRange = Activity(source: .manual, sport: .running, start: day(50), duration: 600)
        try await store.upsert([run, first, second, outOfRange])
        let joined = try #require(Activity.joined([first, second]))
        try await store.saveJoin(joined, components: [first.id, second.id], replacing: [])

        let summaries = try await store.activityListItems(in: day(0)...day(10))
        let full = try await store.activities(in: day(0)...day(10))

        #expect(Set(summaries) == Set(full.map(ActivityListItem.init)))
        #expect(summaries.count == 2)
        let runSummary = try #require(summaries.first { $0.id == run.id })
        #expect(runSummary.distanceMeters == 5000)
        #expect(runSummary.linkedPlanID == planID)
        #expect(runSummary.sport == .running)
        #expect(summaries.contains { $0.id == joined.id })
    }

    @Test("ActivityStore activityListItems keeps nil optionals, and an empty range is empty (MVP2-129)")
    func activityStoreSummariesBare() async throws {
        let store = try makeStore()
        let bare = Activity(source: .manual, sport: .cycling, start: day(1), duration: 600)
        try await store.upsert([bare])

        let items = try await store.activityListItems(in: day(0)...day(10))
        #expect(items == [ActivityListItem(bare)])
        #expect(items.first?.distanceMeters == nil)
        #expect(items.first?.linkedPlanID == nil)
        #expect(try await store.activityListItems(in: day(20)...day(30)).isEmpty)
    }

    @Test("ActivityStore activityListItems returns a join when the range reaches only a later piece (MVP2-129)")
    func activityStoreSummariesLaterPiece() async throws {
        let store = try makeStore()
        let first = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(2), duration: 900)
        let second = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(5), duration: 900)
        try await store.upsert([first, second])
        let joined = try #require(Activity.joined([first, second]))
        try await store.saveJoin(joined, components: [first.id, second.id], replacing: [])

        let items = try await store.activityListItems(in: day(4)...day(6))
        #expect(items.map(\.id) == [joined.id])
    }

    @Test("ActivityStore activities(ids:) returns the stored ones keyed by id, skipping unknown ids")
    func activityStoreBatchLookup() async throws {
        let store = try makeStore()
        let a = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        let b = Activity(source: .manual, sport: .cycling, start: day(1), duration: 3600)
        try await store.upsert([a, b])

        let found = try await store.activities(ids: [a.id, b.id, UUID()])

        #expect(found == [a.id: a, b.id: b])
        #expect(try await store.activities(ids: []).isEmpty)
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
        #expect(try await store.activity(source: .testing) == nil)
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
        let testing = Activity(source: .testing, sport: .running, start: day(3), duration: 1800)
        try await store.upsert([manual, testing])

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
        // Manual and testing activities are untouched -- only the duplicate group sharing a
        // source with a natural key is deduped.
        let remaining = try await store.activities(in: day(0)...day(3))
        #expect(remaining.count == 3)
        #expect(remaining.contains { $0.source == .manual })
        #expect(remaining.contains { $0.source == .testing })
        #expect(remaining.contains { $0.source == source })
    }

    @Test("ActivityStore deduplicateActivities keeps the duplicate with more heart-rate samples, not an arbitrary one")
    func activityStoreDeduplicateActivitiesPrefersMoreCompleteData() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())

        // Simulates the exact scenario this tie-break exists for: the same workout imported both
        // before and after a fix to how HR series samples are unpacked on import. Keeping an
        // arbitrary one of the two (e.g. by smallest id) would have roughly 50% odds of silently
        // reverting that fix for this activity.
        let sparse = Activity(
            source: source, sport: .running, start: day(0), duration: 1800, heartRate: []
        )
        let rich = Activity(
            source: source, sport: .running, start: day(0), duration: 1800,
            heartRate: [HeartRateSample(time: day(0), bpm: 140), HeartRateSample(time: day(0) + 60, bpm: 150)]
        )
        let context = ModelContext(store.modelContainer)
        context.insert(try ActivityRecord(activity: sparse))
        context.insert(try ActivityRecord(activity: rich))
        try context.save()

        let removed = try await store.deduplicateActivities()

        #expect(removed.map(\.id) == [sparse.id])
        let remaining = try await store.activity(source: source)
        #expect(remaining?.id == rich.id)
        #expect(remaining?.heartRate.count == 2)
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

    @Test("ActivityStore upsert never dedupes .testing activities against each other")
    func activityStoreUpsertDoesNotDedupeTestingActivities() async throws {
        let store = try makeStore()
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

    @Test("ActivityStore deleteActivity(source:) never tombstones -- only deleteActivity(id:) does (MVP1-64)")
    func activityStoreDeleteActivityBySourceDoesNotTombstone() async throws {
        // deleteActivity(source:) is the removal path for a source reported gone *at the origin*
        // (ImportResult.deletedSources) -- if the same source legitimately reappears there later
        // (e.g. an un-deleted HealthKit workout), a re-import must be free to add it back. Only
        // deleteActivity(id:) (the athlete's own overlap-resolution action) tombstones.
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])

        try await store.deleteActivity(source: source)

        #expect(try await store.tombstonedSources(among: [source]) == [])
    }

    @Test("ActivityStore deleteActivity(id:) tombstones the source so a re-import can't resurrect it (MVP1-64)")
    func activityStoreDeleteActivityByIDTombstonesSource() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])

        try await store.deleteActivity(id: activity.id)

        #expect(try await store.tombstonedSources(among: [source]) == [source])
        // A re-import building a fresh `Activity` for the same source (since `activity(source:)`
        // now returns nil) would otherwise upsert it right back in -- the resurrection this
        // tombstone exists to prevent, checked by the caller (`TrainingModel`'s import path)
        // before ever calling `upsert(_:)`.
        #expect(try await store.activity(source: source) == nil)
    }

    @Test("ActivityStore deleteActivity(id:) never tombstones a source without a natural key")
    func activityStoreDeleteActivityByIDDoesNotTombstoneManualSource() async throws {
        let store = try makeStore()
        let activity = Activity(source: .manual, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])

        try await store.deleteActivity(id: activity.id)

        #expect(try await store.tombstonedSources(among: [.manual]) == [])
    }

    @Test("ActivityStore upsert clears a source's tombstone once it's genuinely re-added")
    func activityStoreUpsertClearsTombstone() async throws {
        let store = try makeStore()
        let source = ActivitySource.healthKit(UUID())
        let activity = Activity(source: source, sport: .cycling, start: day(0), duration: 3600)
        try await store.upsert([activity])
        try await store.deleteActivity(id: activity.id)
        #expect(try await store.tombstonedSources(among: [source]) == [source])

        try await store.upsert([activity])

        #expect(try await store.tombstonedSources(among: [source]) == [])
        #expect(try await store.activity(source: source) == activity)
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

    @Test("AthleteStore keeps the date of birth (MVP2-124)")
    func athleteStoreKeepsDateOfBirth() async throws {
        let store = try makeStore()
        var profile = AthleteProfile.fixture()
        profile.dateOfBirth = Date(timeIntervalSince1970: 631_152_000)
        try await store.save(profile)

        let fetched = try #require(await store.athleteProfile())

        #expect(fetched.dateOfBirth == profile.dateOfBirth)
        #expect(fetched == profile)
    }

    @Test("AthleteStore keeps the pace history and the HealthKit resting-HR switch (MVP2-132)")
    func athleteStoreKeepsPaceHistoryAndSwitch() async throws {
        let store = try makeStore()
        var profile = AthleteProfile.fixture()
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 280), from: Date(timeIntervalSince1970: 1_700_000_000))
        profile.usesHealthKitRestingHeartRate = false
        try await store.save(profile)

        let fetched = try #require(await store.athleteProfile())

        #expect(fetched == profile)
        #expect(fetched.paceHistory.count == 2)
        #expect(!fetched.usesHealthKitRestingHeartRate)
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

    @Test("CycleStore reads a cycle record written before phases became named values")
    func cycleStoreReadsLegacyPayload() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let id = UUID()
        let legacy = Data("""
        {"id":"\(id.uuidString)","level":{"micro":{}},"phase":{"recovery":{}},"name":"Week 4","dateRange":[1000,2000]}
        """.utf8)
        let context = ModelContext(container)
        context.insert(TrainingCycleRecord(id: id, payload: legacy))
        try context.save()

        let cycle = try #require(try await SwiftDataStore(modelContainer: container).cycle(id: id))

        #expect(cycle.phase == .recovery)
        #expect(cycle.loadRole == .recovery)
    }

    @Test("CycleStore round-trips a paradigm-defined phase and load role")
    func cycleStoreRoundTripsNamedPhase() async throws {
        let store = try makeStore()
        let cycle = TrainingCycle(level: .micro, phase: "structural", loadRole: .build, name: "Week 1", dateRange: day(0)...day(6))
        try await store.upsert([cycle])

        #expect(try await store.cycle(id: cycle.id) == cycle)
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

    // MARK: RaceStore

    @Test("RaceStore upsert/fetch round-trips and filters by date range")
    func raceStoreRoundTrip() async throws {
        let store = try makeStore()
        let inRange = Race(name: "Local 10K", date: day(5), priority: .secondary)
        let outOfRange = Race(name: "Marathon", date: day(50), priority: .primary)

        try await store.upsert([inRange, outOfRange])

        let fetched = try await store.races(in: day(0)...day(10))
        #expect(fetched.map(\.id) == [inRange.id])
        #expect(try await store.race(id: outOfRange.id) == outOfRange)
    }

    @Test("RaceStore upsert replaces an existing race matched by id rather than duplicating")
    func raceStoreUpsertReplaces() async throws {
        let store = try makeStore()
        var race = Race(name: "Local 10K", date: day(5), priority: .tertiary)
        try await store.upsert([race])

        race.name = "Local 10K (renamed)"
        race.priority = .primary
        try await store.upsert([race])

        let stored = try await store.races(in: day(0)...day(10))
        #expect(stored == [race])
    }

    @Test("RaceStore delete removes a race")
    func raceStoreDelete() async throws {
        let store = try makeStore()
        let race = Race(name: "Local 10K", date: day(5), priority: .primary)
        try await store.upsert([race])

        try await store.deleteRace(id: race.id)

        #expect(try await store.race(id: race.id) == nil)
    }

    // MARK: GoalStore

    @Test("GoalStore upsert/fetch round-trips every target kind, replaces by id and deletes")
    func goalStoreRoundTrip() async throws {
        let store = try makeStore()
        var time = Goal(name: "Sub-20 5k", target: .time(sport: .running, distanceMeters: 5000, seconds: 1200), notes: "Parkrun")
        let volume = Goal(name: "1500 km", target: .volume(sport: nil, measure: .distanceMeters, amount: 1_500_000, per: .year))
        let text = Goal(name: "Enjoy running again", target: .freeText)

        try await store.upsert([time, volume, text])
        time.notes = nil
        try await store.upsert([time])

        let stored = try await store.goals()
        #expect(Set(stored) == [time, volume, text])
        #expect(try await store.goal(id: volume.id) == volume)

        try await store.deleteGoal(id: volume.id)
        try await store.deleteGoal(id: UUID())

        #expect(try await store.goal(id: volume.id) == nil)
        #expect(try await store.goals().count == 2)
    }

    @Test("GoalStore skips a record it can't decode instead of failing the whole list (MVP2-139)")
    func goalStoreSkipsUndecodableRecord() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let good = Goal(name: "Sub-20 5k", target: .time(sport: .running, distanceMeters: 5000, seconds: 1200))
        try await store.upsert([good])
        // A target kind a newer version might write: valid JSON, but not a case this version knows.
        let context = ModelContext(container)
        context.insert(GoalRecord(id: UUID(), payload: Data(#"{"id":"\#(UUID().uuidString)","name":"Future","target":{"swim":{}}}"#.utf8)))
        try context.save()

        let goals = try await store.goals()

        #expect(goals == [good])
    }

    // MARK: WorkoutTemplateStore

    @Test("WorkoutTemplateStore upsert/fetch round-trips parameters and parameterised blocks, replaces by id and deletes")
    func templateStoreRoundTrip() async throws {
        let store = try makeStore()
        var intervals = WorkoutTemplate(
            name: "Intervals", titleName: "Reps", sport: .running,
            parameters: [
                WorkoutTemplateParameter(key: "reps", name: "Repeats", unit: .count, defaultValue: 6, range: 2...12),
                WorkoutTemplateParameter(key: "work", name: "Work", unit: .minutes, defaultValue: 3)
            ],
            blocks: [
                TemplateBlock(steps: [TemplateStep(kind: .warmup, goal: .time(.fixed(600)), target: .heartRateZone(2))]),
                TemplateBlock(
                    steps: [
                        TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .heartRateZone(4)),
                        TemplateStep(kind: .recovery, goal: .open)
                    ],
                    repetitions: .parameter("reps")
                )
            ]
        )
        let easy = WorkoutTemplate(name: "Easy", sport: .cycling, parameters: [], blocks: [])

        try await store.upsert([intervals, easy])
        intervals.name = "Track intervals"
        try await store.upsert([intervals])

        let stored = try await store.templates()
        #expect(Set(stored) == [intervals, easy])
        #expect(try await store.template(id: intervals.id) == intervals)

        try await store.deleteTemplate(id: easy.id)
        try await store.deleteTemplate(id: UUID())

        #expect(try await store.template(id: easy.id) == nil)
        #expect(try await store.templates().count == 1)
    }

    @Test("a template saved before archivedDate existed decodes as not archived, and the date round-trips (MVP2-142)")
    func templateStoreArchiveDate() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let old = WorkoutTemplate(name: "Old", sport: .running, parameters: [], blocks: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "archivedDate")
        let context = ModelContext(container)
        context.insert(WorkoutTemplateRecord(id: old.id, payload: try JSONSerialization.data(withJSONObject: json)))
        try context.save()
        #expect(try await store.template(id: old.id)?.isArchived == false)

        var archived = old
        archived.archivedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsert([archived])
        #expect(try await store.template(id: old.id)?.archivedDate == archived.archivedDate)
    }

    @Test("WorkoutTemplateStore skips a record it can't decode instead of failing the whole list (MVP2-140)")
    func templateStoreSkipsUndecodableRecord() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let good = WorkoutTemplate(name: "Easy", sport: .running, parameters: [], blocks: [])
        try await store.upsert([good])
        let context = ModelContext(container)
        context.insert(WorkoutTemplateRecord(id: UUID(), payload: Data(#"{"name":"Future","blocks":"?"}"#.utf8)))
        try context.save()

        let templates = try await store.templates()

        #expect(templates == [good])
    }

    @Test("a template with a step kind this version doesn't know is skipped by both templates() and template(id:)")
    func templateStoreSkipsUnknownStepKind() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let good = WorkoutTemplate(name: "Easy", sport: .running, parameters: [], blocks: [])
        try await store.upsert([good])
        // Right shape, but a step kind a newer version might add.
        let futureID = UUID()
        let future = try JSONEncoder().encode(
            WorkoutTemplate(
                id: futureID, name: "Future", sport: .running, parameters: [],
                blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .open)])]
            )
        )
        let json = String(decoding: future, as: UTF8.self).replacingOccurrences(of: "\"work\"", with: "\"sprint\"")
        let context = ModelContext(container)
        context.insert(WorkoutTemplateRecord(id: futureID, payload: Data(json.utf8)))
        try context.save()

        #expect(try await store.templates() == [good])
        #expect(try await store.template(id: futureID) == nil)
    }

    @Test("RaceStore delete is a no-op for an id that doesn't exist")
    func raceStoreDeleteMissingIsNoOp() async throws {
        let store = try makeStore()
        try await store.deleteRace(id: UUID())
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

    @Test("an activity's recorded steps survive the store with their times, and a payload saved before steps decodes with none (MVP2-146)")
    func activityStepsRoundTrip() async throws {
        let store = try makeStore()
        let steps = [
            ActivityStep(
                block: 0, repetition: 0, step: 0, start: day(1), end: day(1).addingTimeInterval(300), duration: 298,
                distanceMeters: 801.65, averageHeartRateBPM: 112.98, elevationAscendedMeters: 4.11, wasGoalMet: true
            ),
            ActivityStep(
                block: 2, repetition: 3, step: 1, start: day(1).addingTimeInterval(300), end: day(1).addingTimeInterval(600)
            ),
        ]
        let activity = Activity(source: .manual, sport: .running, start: day(1), duration: 600, steps: steps)

        try await store.upsert([activity])

        let fetched = try #require(try await store.activity(id: activity.id))
        #expect(fetched.steps == steps)
        #expect(fetched == activity)

        // A payload written before steps existed has no `steps` key.
        var json = try #require(try JSONSerialization.jsonObject(with: PersistenceCoding.encode(activity)) as? [String: Any])
        json["steps"] = nil
        let legacy = ActivityRecord(
            id: activity.id, sourceKey: activity.source.persistenceKey, start: activity.start,
            payload: try JSONSerialization.data(withJSONObject: json)
        )
        #expect(try legacy.toActivity().steps.isEmpty)
    }

    // MARK: TrainingPlanStore

    @Test("TrainingPlanStore round-trips, keeps one plan active and replaces by id")
    func trainingPlanStoreRoundTrip() async throws {
        let store = try makeStore()
        let first = TrainingPlan(name: "A", status: .active, targetRaceID: UUID(), createdDate: day(0))
        let second = TrainingPlan(name: "B", status: .draft, createdDate: day(1))
        try await store.upsertTrainingPlan(first)
        try await store.upsertTrainingPlan(second)
        #expect(try await store.trainingPlan(id: first.id) == first)

        var activated = second
        activated.status = .active
        try await store.upsertTrainingPlan(activated)
        #expect(try await store.trainingPlan(id: first.id)?.status == .draft)
        #expect(try await store.trainingPlan(id: second.id) == activated)
        #expect(try await store.trainingPlans().count == 2)
        #expect(try await store.trainingPlans().filter { $0.status == .active }.count == 1)
    }

    @Test("deleting a training plan removes its cycles and workouts in the same write, keeps the rest")
    func trainingPlanDeleteCascades() async throws {
        let store = try makeStore()
        let doomed = TrainingPlan(name: "Doomed"), kept = TrainingPlan(name: "Kept")
        try await store.upsertTrainingPlan(doomed)
        try await store.upsertTrainingPlan(kept)
        let workoutID = UUID()
        let future = PlannedActivity(workoutID: workoutID, date: day(5), planID: doomed.id)
        let missed = PlannedActivity(workoutID: workoutID, date: day(-5), planID: doomed.id)
        let other = PlannedActivity(workoutID: workoutID, date: day(5), planID: kept.id)
        let unassigned = PlannedActivity(workoutID: workoutID, date: day(6))
        try await store.upsert([future, missed, other, unassigned])
        let doomedMacro = TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: day(0)...day(30), planID: doomed.id)
        let keptMacro = TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: day(0)...day(30), planID: kept.id)
        try await store.upsert([doomedMacro, keptMacro])

        try await store.deleteTrainingPlan(id: doomed.id)

        #expect(try await store.trainingPlan(id: doomed.id) == nil)
        #expect(try await store.plan(id: future.id) == nil)
        #expect(try await store.plan(id: missed.id) == nil)
        #expect(try await store.plan(id: other.id) != nil)
        #expect(try await store.plan(id: unassigned.id) != nil)
        #expect(try await store.cycle(id: doomedMacro.id) == nil)
        #expect(try await store.cycle(id: keptMacro.id) != nil)
    }

    @Test("a training plan with a completed workout is history: deleting it throws and changes nothing")
    func completedTrainingPlanIsNeverDeleted() async throws {
        let store = try makeStore()
        let plan = TrainingPlan(name: "Done a run", createdDate: day(0))
        try await store.upsertTrainingPlan(plan)
        let done = PlannedActivity(workoutID: UUID(), date: day(-5), completedActivityID: UUID(), planID: plan.id)
        let future = PlannedActivity(workoutID: UUID(), date: day(5), planID: plan.id)
        let cycle = TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: day(-10)...day(30), planID: plan.id)
        try await store.upsert([done, future])
        try await store.upsert([cycle])

        await #expect(throws: TrainingPlanError.hasCompletedWorkouts(plan.id)) {
            try await store.deleteTrainingPlan(id: plan.id)
        }

        #expect(try await store.trainingPlan(id: plan.id) == plan)
        #expect(try await store.plan(id: done.id) == done)
        #expect(try await store.plan(id: future.id) == future)
        #expect(try await store.cycle(id: cycle.id) == cycle)
    }

    @Test("two training plans can hold overlapping macro cycles; one plan can't")
    func trainingPlansOverlapPerPlan() async throws {
        let store = try makeStore()
        func macro(_ range: ClosedRange<Date>, _ plan: UUID) -> TrainingCycle {
            TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: range, planID: plan)
        }
        let a = UUID(), b = UUID()
        try await store.upsert([macro(day(0)...day(30), a)])
        try await store.upsert([macro(day(10)...day(40), b)])
        await #expect(throws: CycleStoreError.self) {
            try await store.upsert([macro(day(5)...day(20), a)])
        }
    }
}

import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("A linked activity takes its plan's sport and venue", .serialized)
struct ActivityAdoptsPlanTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func makeModel(athlete: AthleteProfile = .fixture()) -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private func plan(_ model: TrainingModel, venue: Venue?) async throws -> PlannedActivity {
        let workout = StructuredWorkout(name: "Run", sport: .running, venue: venue, blocks: [])
        let plan = PlannedActivity(workoutID: workout.id, date: day(0))
        try await model.add(workout)
        try await model.add(plan)
        return plan
    }

    @Test("a manual link sets the plan's venue; unlinking leaves it")
    func manualLinkAdopts() async throws {
        let (store, model) = makeModel()
        let plan = try await plan(model, venue: .indoor(.treadmill))
        let activity = Activity(source: .healthKit(UUID()), sport: .hiking, venue: .outdoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        try await model.linkActivity(id: activity.id, toPlan: plan.id, asOf: day(0))

        let stored = try #require(try await store.activity(id: activity.id))
        #expect(stored.sport == .running)
        #expect(stored.venue == .indoor(.treadmill))
        #expect(!stored.isSportEdited)
    }

    @Test("a plan without a venue gives the athlete's usual one, or else keeps the recorded venue")
    func fallsBackToAthleteDefault() async throws {
        var athlete = AthleteProfile.fixture()
        athlete.mainSport = .running
        athlete.mainVenue = .outdoor(.road)
        let (store, model) = makeModel(athlete: athlete)
        let plan = try await plan(model, venue: nil)
        let activity = Activity(source: .healthKit(UUID()), sport: .running, venue: .indoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        try await model.linkActivity(id: activity.id, toPlan: plan.id, asOf: day(0))
        #expect(try await store.activity(id: activity.id)?.venue == .outdoor(.road))

        let adopted = activity.adoptingSportAndVenue(
            of: StructuredWorkout(name: "Run", sport: .running, blocks: []), athlete: .fixture()
        )
        #expect(adopted.venue == .indoor(nil))
    }

    @Test("a sport and venue the athlete chose are kept")
    func editedIsKept() async throws {
        let (store, model) = makeModel()
        let plan = try await plan(model, venue: .indoor(.treadmill))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, venue: .outdoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))
        try await model.setSport(.running, venue: .outdoor(.trail), forActivityID: activity.id, asOf: day(0))

        try await model.linkActivity(id: activity.id, toPlan: plan.id, asOf: day(0))

        #expect(try await store.activity(id: activity.id)?.venue == .outdoor(.trail))
    }

    @Test("an automatic match adopts the plan's surface, and a re-import keeps it")
    func automaticMatchAndReimport() async throws {
        let (store, model) = makeModel()
        _ = try await plan(model, venue: .outdoor(.trail))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, venue: .outdoor(nil), start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))
        #expect(try await store.activity(id: activity.id)?.venue == .outdoor(.trail))

        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))
        #expect(try await store.activity(id: activity.id)?.venue == .outdoor(.trail))
    }
}

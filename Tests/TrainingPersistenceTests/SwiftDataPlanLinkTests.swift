import Foundation
import Testing
import TrainingCore
@testable import TrainingPersistence

/// MVP2-134 plan freeing against the real `SwiftDataStore`, whose `activities(ids:)` is its own
/// implementation rather than the protocol default `InMemoryStore` uses.
@MainActor
@Suite("TrainingModel plan linking + SwiftData", .serialized)
struct SwiftDataPlanLinkTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    @Test("a plan completed on another device is freed for the exact match, but not for a same-day guess")
    func planHeldByUnknownActivity() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
            raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        let w = StructuredWorkout(
            name: "W", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        try await model.add(w, asOf: day(0))
        let started = PlannedActivity(workoutID: w.id, date: day(0), completedActivityID: UUID())
        let other = PlannedActivity(workoutID: w.id, date: day(0), completedActivityID: UUID())
        try await model.add(started, asOf: day(0))
        try await model.add(other, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))

        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800, scheduledPlanID: started.id
        )
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        #expect(try await store.plan(id: started.id)?.completedActivityID == activity.id)
        #expect(try await store.plan(id: other.id)?.completedActivityID == other.completedActivityID)
    }
}

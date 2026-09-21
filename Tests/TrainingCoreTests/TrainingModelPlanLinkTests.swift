import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel plan linking", .serialized)
struct TrainingModelPlanLinkTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    private func workout(minutes: Double) -> StructuredWorkout {
        StructuredWorkout(name: "W", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60))])])
    }

    @Test("import links a newly imported activity to its plan")
    func importLinks() async throws {
        let (store, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))

        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        #expect(model.activities.first?.linkedPlanID == plan.id)
        #expect(try await store.plan(id: plan.id)?.completedActivityID == activity.id)
    }

    @Test("a re-import keeps an existing link, and an unlinked activity isn't re-matched")
    func reimportKeepsLinkState() async throws {
        let (_, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        let importer = StubImporter(activities: [activity])
        try await model.importActivities(from: importer, asOf: day(0))

        try await model.importActivities(from: importer, asOf: day(0))
        #expect(model.activities.first?.linkedPlanID == plan.id)

        try await model.unlinkActivity(id: activity.id, asOf: day(0))
        try await model.importActivities(from: importer, asOf: day(0))
        #expect(model.activities.first?.linkedPlanID == nil)
        #expect(model.plans.first?.completedActivityID == nil)
    }

    @Test("manual link moves the plan from its previous activity and clears the ambiguity flag")
    func manualLinkReplacesPrevious() async throws {
        let (store, model) = makeModel()
        let w1 = workout(minutes: 30), w2 = workout(minutes: 31)
        try await model.add(w1, asOf: day(0))
        try await model.add(w2, asOf: day(0))
        let p1 = PlannedActivity(workoutID: w1.id, date: day(0))
        let p2 = PlannedActivity(workoutID: w2.id, date: day(0))
        try await model.add(p1, asOf: day(0))
        try await model.add(p2, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let a = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 30 * 60)
        try await model.importActivities(from: StubImporter(activities: [a]), asOf: day(0))
        #expect(model.planMatchAmbiguities.map(\.activityID) == [a.id])
        let linkedPlanID = try #require(model.activities.first?.linkedPlanID)
        let otherPlanID = linkedPlanID == p1.id ? p2.id : p1.id

        try await model.linkActivity(id: a.id, toPlan: otherPlanID, asOf: day(0))

        #expect(model.activities.first?.linkedPlanID == otherPlanID)
        #expect(try await store.plan(id: otherPlanID)?.completedActivityID == a.id)
        #expect(try await store.plan(id: linkedPlanID)?.completedActivityID == nil)
        #expect(model.planMatchAmbiguities.isEmpty)
    }
}

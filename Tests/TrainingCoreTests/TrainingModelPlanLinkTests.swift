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
            cycleStore: store, raceStore: store, athleteStore: store
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
        // Not just the store: `plans` must reflect the auto-match too, or a UI reading straight off
        // the model (like the week view) keeps showing the plan as unmatched until the next full load.
        #expect(model.plans.first?.completedActivityID == activity.id)
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

    // MARK: Same-day rule

    @Test("a manual link across days is refused and changes nothing")
    func manualLinkCrossDayRefused() async throws {
        let (store, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(1))
        try await model.add(plan, asOf: day(0))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])
        try await model.load(in: day(0)...day(2), asOf: day(0))

        await #expect(throws: PlanLinkError.differentDay) {
            try await model.linkActivity(id: activity.id, toPlan: plan.id, asOf: day(0))
        }
        #expect(try await store.activity(id: activity.id)?.linkedPlanID == nil)
        #expect(try await store.plan(id: plan.id)?.completedActivityID == nil)
    }

    // MARK: Consistency with joins, deletes and failures

    /// A model with one plan and two back-to-back pieces on the same day, the first linked to the plan.
    private func linkedPair() async throws -> (InMemoryStore, TrainingModel, PlannedActivity, Activity, Activity) {
        let (store, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let a = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1500)
        try await model.importActivities(from: StubImporter(activities: [a]), asOf: day(0))
        let b = Activity(source: .healthKit(UUID()), sport: .running, start: day(0).addingTimeInterval(1520), duration: 300)
        try await store.upsert([b])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        #expect(try await store.activity(id: a.id)?.linkedPlanID == plan.id)
        return (store, model, plan, a, b)
    }

    @Test("joining a linked piece hands the plan to the join, and unlinking the join frees it")
    func joinHandsOverPlan() async throws {
        let (store, model, plan, a, b) = try await linkedPair()

        try await model.joinActivities(a.id, b.id, asOf: day(0))
        let join = try #require(model.activities.first)
        #expect(join.linkedPlanID == plan.id)
        #expect(try await store.plan(id: plan.id)?.completedActivityID == join.id)

        try await model.unlinkActivity(id: join.id, asOf: day(0))
        #expect(try await store.plan(id: plan.id)?.completedActivityID == nil)
    }

    @Test("unjoining hands the plan back to a piece")
    func unjoinHandsBackPlan() async throws {
        let (store, model, plan, a, b) = try await linkedPair()
        try await model.joinActivities(a.id, b.id, asOf: day(0))
        let joinID = try #require(model.activities.first?.id)

        try await model.unjoinActivity(id: joinID, asOf: day(0))

        #expect(try await store.plan(id: plan.id)?.completedActivityID == a.id)
        #expect(try await store.activity(id: a.id)?.linkedPlanID == plan.id)
    }

    @Test("deleting a linked activity frees its plan")
    func deleteActivityFreesPlan() async throws {
        let (store, model, plan, a, _) = try await linkedPair()

        try await model.deleteActivity(id: a.id, asOf: day(0))

        #expect(try await store.plan(id: plan.id)?.completedActivityID == nil)
    }

    @Test("deleting a plan frees its activity")
    func deletePlanFreesActivity() async throws {
        let (store, model, plan, a, _) = try await linkedPair()

        try await model.deletePlan(id: plan.id, asOf: day(0))

        #expect(try await store.activity(id: a.id)?.linkedPlanID == nil)
        #expect(model.activities.first { $0.id == a.id }?.linkedPlanID == nil)
    }

    /// Plan store that can be made to fail its reads, to exercise import's best-effort matching.
    private actor FlakyPlanStore: PlanStore {
        let base: InMemoryStore
        var failReads = false
        init(base: InMemoryStore) { self.base = base }
        func setFailReads(_ value: Bool) { failReads = value }
        func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
            if failReads { throw PlanLinkError.differentDay }
            return try await base.plans(in: range)
        }
        func upsert(_ plans: [PlannedActivity]) async throws { try await base.upsert(plans) }
        func plan(id: UUID) async throws -> PlannedActivity? { try await base.plan(id: id) }
        func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
    }

    @Test("a failure matching plans doesn't fail the import or leave the model stale")
    func matchingFailureIsBestEffort() async throws {
        let store = InMemoryStore()
        let planStore = FlakyPlanStore(base: store)
        let model = TrainingModel(
            stores: StoreSet(activityStore: store, planStore: planStore, workoutStore: store, cycleStore: store, raceStore: store, athleteStore: store),
            athlete: AthleteProfile.fixture()
        )
        try await model.load(in: day(0)...day(1), asOf: day(0))
        await planStore.setFailReads(true)

        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        #expect(model.activities.map(\.id) == [activity.id])
    }

    @Test("reconcilePlans links an already-stored activity once its plan exists")
    func reconcilePlansLinksExisting() async throws {
        let (store, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        #expect(model.activities.first?.linkedPlanID == nil)

        try await model.reconcilePlans(asOf: day(0))

        #expect(model.activities.first?.linkedPlanID == plan.id)
        #expect(model.plans.first?.completedActivityID == activity.id)
    }

    @Test("reconcilePlans completes a half-made link and drops dangling ones")
    func repairsHalfLinks() async throws {
        let (store, model) = makeModel()
        let w = workout(minutes: 30)
        try await model.add(w, asOf: day(0))
        let plan = PlannedActivity(workoutID: w.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        // Half link: the activity names the plan, the plan doesn't name it back.
        let halfLinked = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800, linkedPlanID: plan.id)
        // Dangling: names a plan that doesn't exist.
        let dangling = Activity(source: .healthKit(UUID()), sport: .cycling, start: day(0), duration: 1800, linkedPlanID: UUID())
        try await store.upsert([halfLinked, dangling])
        try await model.load(in: day(0)...day(1), asOf: day(0))

        try await model.reconcilePlans(asOf: day(0))

        #expect(try await store.plan(id: plan.id)?.completedActivityID == halfLinked.id)
        #expect(try await store.activity(id: dangling.id)?.linkedPlanID == nil)
    }
}

import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("Training plans", .serialized)
struct TrainingPlanTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel(withPlanStore: Bool = true) -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store,
            trainingPlanStore: withPlanStore ? store : nil
        )
        return (store, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    private func workout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(3))])]
        )
    }

    private func macro(_ range: ClosedRange<Date>, planID: UUID?) -> TrainingCycle {
        TrainingCycle(level: .macro, phase: .base, name: "Macro", dateRange: range, planID: planID)
    }

    private var totalLoad: (TrainingModel) -> Double { { $0.metrics.reduce(0) { $0 + $1.load } } }

    // MARK: - Stored payloads

    @Test("a planned activity and a cycle stored before plans existed decode with no plan")
    func legacyPayloadsDecode() throws {
        func stripped<T: Codable>(_ value: T) throws -> T {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            json.removeValue(forKey: "planID")
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let plan = PlannedActivity(workoutID: UUID(), date: day(1), planID: UUID())
        let cycle = macro(day(0)...day(6), planID: UUID())
        #expect(try stripped(plan).planID == nil)
        #expect(try stripped(cycle).planID == nil)
        #expect(try JSONDecoder().decode(PlannedActivity.self, from: JSONEncoder().encode(plan)) == plan)
    }

    // MARK: - Store

    @Test("storing an active plan demotes the plan that was active")
    func upsertKeepsOneActive() async throws {
        let store = InMemoryStore()
        let first = TrainingPlan(name: "A", status: .active)
        let second = TrainingPlan(name: "B", status: .active)
        try await store.upsertTrainingPlan(first)
        try await store.upsertTrainingPlan(second)
        let stored = try await store.trainingPlans()
        #expect(stored.first { $0.id == first.id }?.status == .draft)
        #expect(stored.first { $0.id == second.id }?.status == .active)
        try await store.upsertTrainingPlan(TrainingPlan(name: "Draft", status: .draft))
        #expect(try await store.trainingPlans().filter { $0.status == .active }.count == 1)
    }

    @Test("deleting a plan removes its cycles and workouts and leaves other plans' items")
    func deleteCascades() async throws {
        let store = InMemoryStore()
        let doomed = TrainingPlan(name: "Doomed"), kept = TrainingPlan(name: "Kept")
        try await store.upsertTrainingPlan(doomed)
        try await store.upsertTrainingPlan(kept)
        let workoutID = UUID()
        let future = PlannedActivity(workoutID: workoutID, date: day(5), planID: doomed.id)
        let missed = PlannedActivity(workoutID: workoutID, date: day(-5), planID: doomed.id)
        let other = PlannedActivity(workoutID: workoutID, date: day(5), planID: kept.id)
        try await store.upsert([future, missed, other])
        let doomedMacro = macro(day(0)...day(30), planID: doomed.id)
        let keptMacro = macro(day(0)...day(30), planID: kept.id)
        try await store.upsert([doomedMacro, keptMacro])

        try await store.deleteTrainingPlan(id: doomed.id)

        #expect(try await store.trainingPlan(id: doomed.id) == nil)
        #expect(try await store.plan(id: future.id) == nil)
        #expect(try await store.plan(id: missed.id) == nil)
        #expect(try await store.plan(id: other.id) != nil)
        #expect(try await store.cycle(id: doomedMacro.id) == nil)
        #expect(try await store.cycle(id: keptMacro.id) != nil)
        try await store.deleteTrainingPlan(id: doomed.id) // a second delete is a no-op
    }

    @Test("a plan with a completed workout is history: deleting it throws and changes nothing")
    func completedPlanIsNeverDeleted() async throws {
        let store = InMemoryStore()
        let plan = TrainingPlan(name: "Done a run")
        try await store.upsertTrainingPlan(plan)
        let done = PlannedActivity(workoutID: UUID(), date: day(-5), completedActivityID: UUID(), planID: plan.id)
        let future = PlannedActivity(workoutID: UUID(), date: day(5), planID: plan.id)
        let cycle = macro(day(-10)...day(30), planID: plan.id)
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

    @Test("two plans can lay out overlapping cycles; one plan can't")
    func overlapIsPerPlan() async throws {
        let store = InMemoryStore()
        let planA = UUID(), planB = UUID()
        try await store.upsert([macro(day(0)...day(30), planID: planA)])
        try await store.upsert([macro(day(10)...day(40), planID: planB)])
        await #expect(throws: CycleStoreError.self) {
            try await store.upsert([self.macro(day(5)...day(20), planID: planA)])
        }
    }

    // MARK: - Model

    @Test("a draft plan's workouts don't feed the series until the plan is activated")
    func onlyActivePlanFeedsSeries() async throws {
        let (_, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        let active = try await model.createTrainingPlan(named: "Now", status: .active, asOf: day(0))
        let draft = try await model.createTrainingPlan(named: "Alternative", asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        let baseline = totalLoad(model)

        try await model.add(PlannedActivity(workoutID: w.id, date: day(3), planID: draft.id), asOf: day(0))
        #expect(model.plans.isEmpty)
        #expect(totalLoad(model) == baseline)
        #expect(try await model.plannedActivities(ofPlan: draft.id, in: day(0)...day(10)).count == 1)

        try await model.activateTrainingPlan(id: draft.id, asOf: day(0))
        #expect(model.plans.count == 1)
        #expect(totalLoad(model) > baseline)
        #expect(model.activeTrainingPlan?.id == draft.id)
        #expect(model.trainingPlans.first { $0.id == active.id }?.status == .draft)

        try await model.setStatus(.archived, ofTrainingPlan: draft.id, asOf: day(0))
        #expect(model.plans.isEmpty)
        #expect(totalLoad(model) == baseline)
        #expect(model.activeTrainingPlan == nil)
    }

    @Test("only the active plan's cycles are in the model")
    func onlyActivePlanCycles() async throws {
        let (_, model) = makeModel()
        let active = try await model.createTrainingPlan(named: "Now", status: .active, asOf: day(0))
        let draft = try await model.createTrainingPlan(named: "Alt", asOf: day(0))
        try await model.load(in: day(0)...day(30), asOf: day(0))
        try await model.add([macro(day(0)...day(20), planID: active.id), macro(day(0)...day(25), planID: draft.id)], asOf: day(0))
        #expect(model.cycles.map(\.planID) == [active.id])
        #expect(try await model.cycles(ofPlan: draft.id, in: day(0)...day(30)).count == 1)
    }

    @Test("a workout added by hand with no plan lands in the active plan, creating 'My plan' if there is none")
    func manualWorkoutGoesInActivePlan() async throws {
        let (store, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        #expect(model.trainingPlans.isEmpty)

        let first = PlannedActivity(workoutID: w.id, date: day(2))
        try await model.add(first, asOf: day(0))
        let created = try #require(try await store.trainingPlans().first)
        #expect(created.name == "My plan" && created.status == .active)
        #expect(try await store.plan(id: first.id)?.planID == created.id)

        let second = PlannedActivity(workoutID: w.id, date: day(3))
        try await model.add(second, asOf: day(0))
        #expect(try await store.trainingPlans().count == 1)
        #expect(try await store.plan(id: second.id)?.planID == created.id)
    }

    @Test("loading adopts workouts and cycles stored before plans existed into a 'Current plan'")
    func loadAdoptsUnassigned() async throws {
        let (store, model) = makeModel()
        let w = workout()
        try await store.upsert([w])
        let legacy = PlannedActivity(workoutID: w.id, date: day(2))
        let legacyMacro = macro(day(0)...day(10), planID: nil)
        try await store.upsert([legacy])
        try await store.upsert([legacyMacro])

        try await model.load(in: day(0)...day(10), asOf: day(0))

        let plan = try #require(model.activeTrainingPlan)
        #expect(plan.name == "Current plan")
        #expect(try await store.plan(id: legacy.id)?.planID == plan.id)
        #expect(try await store.cycle(id: legacyMacro.id)?.planID == plan.id)
        #expect(model.plans.count == 1 && model.cycles.count == 1)

        try await model.load(in: day(0)...day(10), asOf: day(0))
        #expect(try await store.trainingPlans().count == 1)
    }

    @Test("unassigned items still count when a plan is archived behind their back")
    func unassignedItemsCount() async throws {
        let store = InMemoryStore()
        let w = workout()
        try await store.upsert([w])
        try await store.upsertTrainingPlan(TrainingPlan(name: "Old", status: .archived))
        try await store.upsert([PlannedActivity(workoutID: w.id, date: day(2))])
        let plans = try await StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
            raceStore: store, athleteStore: store, trainingPlanStore: store
        ).activePlannedActivities(in: day(0)...day(10))
        #expect(plans.count == 1)
    }

    @Test("without a plan store everything counts and plan operations throw notConfigured")
    func withoutPlanStore() async throws {
        let (_, model) = makeModel(withPlanStore: false)
        let w = workout()
        try await model.add(w, asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        try await model.add(PlannedActivity(workoutID: w.id, date: day(2)), asOf: day(0))
        #expect(model.plans.count == 1 && model.plans[0].planID == nil)
        await #expect(throws: TrainingPlanError.notConfigured) {
            try await model.createTrainingPlan(named: "X", asOf: self.day(0))
        }
    }

    @Test("duplicating a plan copies its cycles (parents remapped) and its uncompleted future workouts as a draft")
    func duplicate() async throws {
        let (store, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        let original = try await model.createTrainingPlan(named: "Marathon", status: .active, asOf: day(0))
        try await model.load(in: day(-10)...day(30), asOf: day(0))
        let macroCycle = macro(day(0)...day(20), planID: original.id)
        let meso = TrainingCycle(level: .meso, phase: .base, name: "Meso", dateRange: day(0)...day(10), parentID: macroCycle.id, planID: original.id)
        try await model.add([macroCycle, meso], asOf: day(0))
        try await model.add(PlannedActivity(workoutID: w.id, date: day(3), planID: original.id), asOf: day(0))
        try await model.add(PlannedActivity(workoutID: w.id, date: day(-3), planID: original.id), asOf: day(0)) // past
        try await model.add(PlannedActivity(workoutID: w.id, date: day(4), completedActivityID: UUID(), planID: original.id), asOf: day(0))

        let copy = try await model.duplicateTrainingPlan(id: original.id, asOf: day(0))

        #expect(copy.name == "Marathon copy" && copy.status == .draft)
        #expect(model.activeTrainingPlan?.id == original.id)
        let copiedPlans = try await model.plannedActivities(ofPlan: copy.id, in: day(-10)...day(30))
        #expect(copiedPlans.map(\.date) == [day(3)])
        let copiedCycles = try await model.cycles(ofPlan: copy.id, in: day(0)...day(30))
        #expect(copiedCycles.count == 2)
        let copiedMacro = try #require(copiedCycles.first { $0.level == .macro })
        #expect(copiedCycles.first { $0.level == .meso }?.parentID == copiedMacro.id)
        #expect(copiedMacro.id != macroCycle.id)
        #expect(try await store.plan(id: copiedPlans[0].id)?.completedActivityID == nil)
    }

    @Test("deleting a plan through the model drops its workouts from the series")
    func deleteThroughModel() async throws {
        let (_, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        let plan = try await model.createTrainingPlan(named: "Now", status: .active, asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        let empty = totalLoad(model)
        try await model.add(PlannedActivity(workoutID: w.id, date: day(3), planID: plan.id), asOf: day(0))
        #expect(totalLoad(model) > empty)

        try await model.deleteTrainingPlan(id: plan.id, asOf: day(0))
        #expect(model.plans.isEmpty && model.trainingPlans.isEmpty)
        #expect(totalLoad(model) == empty)
    }

    @Test("an imported activity isn't matched to a draft plan's workout")
    func draftWorkoutsAreNotMatched() async throws {
        struct StubImporter: ActivityImporting {
            let activities: [Activity]
            func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
                ImportResult(upserted: activities, deletedSources: [], anchor: nil)
            }
        }
        let (store, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        _ = try await model.createTrainingPlan(named: "Now", status: .active, asOf: day(0))
        let draft = try await model.createTrainingPlan(named: "Alt", asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        let draftPlan = PlannedActivity(workoutID: w.id, date: day(0), planID: draft.id)
        try await model.add(draftPlan, asOf: day(0))

        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 3600)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))

        #expect(try await store.plan(id: draftPlan.id)?.completedActivityID == nil)
    }

    @Test("the model refuses to delete a plan with a completed workout, and says so beforehand")
    func modelRefusesCompletedPlan() async throws {
        let (store, model) = makeModel()
        let w = workout()
        try await model.add(w, asOf: day(0))
        let plan = try await model.createTrainingPlan(named: "Now", status: .active, asOf: day(0))
        let empty = try await model.createTrainingPlan(named: "Empty", asOf: day(0))
        try await model.load(in: day(0)...day(10), asOf: day(0))
        let done = PlannedActivity(workoutID: w.id, date: day(0), completedActivityID: UUID(), planID: plan.id)
        try await store.upsert([done])

        #expect(try await model.trainingPlanHasCompletedWorkouts(id: plan.id))
        #expect(try await model.trainingPlanHasCompletedWorkouts(id: empty.id) == false)
        await #expect(throws: TrainingPlanError.hasCompletedWorkouts(plan.id)) {
            try await model.deleteTrainingPlan(id: plan.id, asOf: self.day(0))
        }
        #expect(model.trainingPlans.count == 2)
        try await model.setStatus(.archived, ofTrainingPlan: plan.id, asOf: day(0)) // archiving stays possible
        try await model.deleteTrainingPlan(id: empty.id, asOf: day(0))
        #expect(model.trainingPlans.map(\.id) == [plan.id])
    }
}

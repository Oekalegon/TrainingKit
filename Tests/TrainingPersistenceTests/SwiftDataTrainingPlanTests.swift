import Foundation
import SwiftData
import Testing
import TrainingCore
@testable import TrainingPersistence

@MainActor
@Suite("Training plans on SwiftDataStore", .serialized)
struct SwiftDataTrainingPlanTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() throws -> (SwiftDataStore, StoreSet) {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
            raceStore: store, athleteStore: store, trainingPlanStore: store
        )
        return (store, stores)
    }

    private func workout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(3))])]
        )
    }

    @Test("loading adopts unassigned data into one fixed plan and keeps a completed link")
    func adoption() async throws {
        let (store, stores) = try makeStores()
        let w = workout()
        try await store.upsert([w])
        let linked = PlannedActivity(workoutID: w.id, date: day(2), completedActivityID: UUID())
        let plain = PlannedActivity(workoutID: w.id, date: day(3))
        try await store.upsert([linked, plain])
        let macro = TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: day(0)...day(20))
        try await store.upsert([macro])

        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        try await model.load(in: day(0)...day(10), asOf: day(0))

        #expect(model.activeTrainingPlan?.id == TrainingPlan.currentPlanID)
        #expect(try await store.plan(id: linked.id)?.completedActivityID == linked.completedActivityID)
        #expect(try await store.plan(id: plain.id)?.planID == TrainingPlan.currentPlanID)
        #expect(try await store.cycle(id: macro.id)?.planID == TrainingPlan.currentPlanID)
        #expect(try await store.trainingPlans().count == 1)
        #expect(model.plans.count == 2 && model.cycles.count == 1)
    }

    @Test("a new plan replaces a followed one: the old plan is cancelled, kept, and its completed workout still shows")
    func replaceAndCancel() async throws {
        let (store, stores) = try makeStores()
        let w = workout()
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        try await model.add(w, asOf: day(0))
        let old = try await model.createTrainingPlan(named: "Old", status: .active, asOf: day(0))
        let done = PlannedActivity(workoutID: w.id, date: day(-3), completedActivityID: UUID(), planID: old.id)
        try await store.upsert([done])
        try await model.load(in: day(-10)...day(10), asOf: day(0))

        let new = try await model.createTrainingPlan(named: "New", status: .active, asOf: day(0))

        let stored = try await store.trainingPlan(id: old.id)
        #expect(stored?.status == .cancelled && stored?.cancelledDate != nil)
        #expect(try await store.trainingPlan(id: new.id)?.status == .active)
        #expect(model.plans.map(\.id) == [done.id])
        await #expect(throws: TrainingPlanError.hasCompletedWorkouts(old.id)) {
            try await model.deleteTrainingPlan(id: old.id, asOf: self.day(0))
        }
    }

    @Test("duplicating a plan copies it in one write, and a failing copy leaves nothing behind")
    func duplicate() async throws {
        let (store, stores) = try makeStores()
        let w = workout()
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        try await model.add(w, asOf: day(0))
        let plan = try await model.createTrainingPlan(named: "Base", status: .active, asOf: day(0))
        try await model.load(in: day(-5)...day(30), asOf: day(0))
        let macro = TrainingCycle(level: .macro, phase: .base, name: "M", dateRange: day(0)...day(20), planID: plan.id)
        try await model.add([macro], asOf: day(0))
        try await model.add(PlannedActivity(workoutID: w.id, date: day(3), planID: plan.id), asOf: day(0))

        let copy = try await model.duplicateTrainingPlan(id: plan.id, asOf: day(0))

        #expect(copy.status == .draft)
        #expect(try await model.cycles(ofPlan: copy.id, in: day(0)...day(30)).count == 1)
        #expect(try await model.plannedActivities(ofPlan: copy.id, in: day(0)...day(30)).count == 1)

        let overlapping = [macro, TrainingCycle(level: .macro, phase: .base, name: "M2", dateRange: day(10)...day(30), planID: copy.id)]
        let doomed = TrainingPlan(name: "Doomed")
        await #expect(throws: CycleStoreError.self) {
            try await store.insertTrainingPlan(doomed, cycles: overlapping.map { var c = $0; c.planID = doomed.id; return c }, plannedActivities: [])
        }
        #expect(try await store.trainingPlan(id: doomed.id) == nil)
    }

    @Test("committing a proposal stores its workouts, cycles and planned workouts, and activation keeps one active plan")
    func commitProposal() async throws {
        let (store, stores) = try makeStores()
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture())
        let proposed = workout()
        let macro = TrainingCycle(level: .macro, phase: .base, name: "Macro", dateRange: day(0)...day(13))
        let candidate = PlanCandidate(
            cycles: [macro], plannedActivities: [PlannedActivity(workoutID: proposed.id, date: day(2))],
            workouts: [proposed], sessions: [], metrics: []
        )
        let proposal = PlanProposal(
            candidate: candidate, evaluation: PlanEvaluation(findings: []), compromises: [],
            levers: .none, outcome: .acceptable, today: day(0)
        )

        let draft = try await model.commit(proposal, named: "Draft", asOf: day(0))
        #expect(try await store.trainingPlan(id: draft.id)?.status == .draft)
        #expect(try await store.workout(id: proposed.id) != nil)
        #expect(try await model.cycles(ofPlan: draft.id, in: day(-1)...day(20)).count == 1)
        #expect(try await model.plannedActivities(ofPlan: draft.id, in: day(-1)...day(20)).count == 1)

        let active = try await model.commit(proposal, named: "Active", activate: true, asOf: day(0))
        let plans = try await store.trainingPlans()
        #expect(plans.filter { $0.status == .active }.map(\.id) == [active.id])
    }
}

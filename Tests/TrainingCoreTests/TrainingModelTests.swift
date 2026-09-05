import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel")
struct TrainingModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, stores)
    }

    private func steadyWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("load(in:) populates state from the stores")
    func loadPopulatesState() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))

        try await store.upsert([workout])
        try await store.upsert([plan])
        try await store.upsert([meso])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(13), asOf: day(3))

        #expect(model.workouts.map(\.id) == [workout.id])
        #expect(model.plans.map(\.id) == [plan.id])
        #expect(model.cycles.map(\.id) == [meso.id])
        #expect(!model.metrics.isEmpty)
    }

    @Test("add(_ plan:) persists to the store and updates metrics")
    func addPlanPersistsAndRecomputes() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(0))
        #expect(model.metrics.allSatisfy { $0.load == 0 })

        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await model.add(plan, asOf: day(0))

        #expect(model.plans.map(\.id) == [plan.id])
        #expect(try await store.plan(id: plan.id) == plan)
        let planDayMetrics = model.metrics.first { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: day(5)) }
        #expect((planDayMetrics?.load ?? 0) > 0)
    }

    @Test("add(_ cycles:) persists to the store and updates local state")
    func addCyclesPersistsAndUpdates() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(13), asOf: day(0))
        #expect(model.cycles.isEmpty)

        let meso = TrainingCycle(level: .meso, phase: .build, name: "Meso 1", dateRange: day(0)...day(13))
        try await model.add([meso], asOf: day(0))

        #expect(model.cycles.map(\.id) == [meso.id])
        #expect(try await store.cycle(id: meso.id) == meso)
    }

    @Test("recompute(asOf:) is deterministic for a fixed today")
    func recomputeIsDeterministic() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await store.upsert([workout])
        try await store.upsert([plan])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(10), asOf: day(3))
        let firstRun = model.metrics

        await model.recompute(asOf: day(3))
        let secondRun = model.metrics

        #expect(firstRun.map(\.load) == secondRun.map(\.load))
        #expect(firstRun.map(\.ctl) == secondRun.map(\.ctl))
    }

    @Test("add(_ plan:) reflects the addition even if load(in:) was never called")
    func addPlanWithoutPriorLoad() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        let model = TrainingModel(stores: stores, athlete: athlete)
        let plan = PlannedActivity(workoutID: workout.id, date: day(0))
        try await model.add(plan, asOf: day(0))

        #expect(model.plans.map(\.id) == [plan.id])
        #expect(try await store.plan(id: plan.id) == plan)
        #expect(model.metrics.contains { $0.load > 0 })
    }

    @Test("a failed load(in:) leaves the model unchanged rather than partially updated")
    func failedLoadLeavesModelUnchanged() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])

        var throwingStores = stores
        throwingStores.planStore = ThrowingPlanStore()
        let model = TrainingModel(stores: throwingStores, athlete: athlete)

        await #expect(throws: (any Error).self) {
            try await model.load(in: day(0)...day(1), asOf: day(0))
        }

        #expect(model.activities.isEmpty)
        #expect(model.metrics.isEmpty)
    }
}

private struct ThrowingPlanStore: PlanStore {
    struct Boom: Error {}
    func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] { throw Boom() }
    func upsert(_ plans: [PlannedActivity]) async throws {}
    func plan(id: UUID) async throws -> PlannedActivity? { nil }
    func deletePlan(id: UUID) async throws {}
}

import Foundation
import Testing
@testable import TrainingCore

/// Proves the pattern the design doc's "Multiple athletes" section describes actually works: a
/// host app supporting several athletes constructs one `StoreSet`/`TrainingModel` per athlete, and
/// nothing in `TrainingCore` needs to change for that to produce fully independent results — because
/// isolation comes from using separate store instances, not from filtering shared rows within one.
@MainActor
@Suite("Multi-athlete store isolation")
struct MultiAthleteStoreIsolationTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() -> StoreSet {
        let store = InMemoryStore()
        return StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
    }

    private func workout(name: String) -> StructuredWorkout {
        StructuredWorkout(
            name: name, sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("two athletes' TrainingModels, each backed by its own StoreSet, never see each other's data")
    func modelsStayIndependent() async throws {
        let athleteA = AthleteProfile.fixture(name: "Athlete A")
        let athleteB = AthleteProfile.fixture(name: "Athlete B")
        #expect(athleteA.id != athleteB.id)

        let storesA = makeStores()
        let storesB = makeStores()

        let workoutA = workout(name: "A's easy run")
        let workoutB = workout(name: "B's easy run")
        try await storesA.workoutStore.upsert([workoutA])
        try await storesB.workoutStore.upsert([workoutB])

        let planA = PlannedActivity(workoutID: workoutA.id, date: day(5))
        let planB1 = PlannedActivity(workoutID: workoutB.id, date: day(3))
        let planB2 = PlannedActivity(workoutID: workoutB.id, date: day(6))
        try await storesA.planStore.upsert([planA])
        try await storesB.planStore.upsert([planB1, planB2])

        let modelA = TrainingModel(stores: storesA, athlete: athleteA)
        let modelB = TrainingModel(stores: storesB, athlete: athleteB)

        try await modelA.load(in: day(0)...day(13), asOf: day(0))
        try await modelB.load(in: day(0)...day(13), asOf: day(0))

        #expect(modelA.plans.map(\.id) == [planA.id])
        #expect(modelA.workouts.map(\.id) == [workoutA.id])

        #expect(Set(modelB.plans.map(\.id)) == Set([planB1.id, planB2.id]))
        #expect(modelB.workouts.map(\.id) == [workoutB.id])

        // Neither model's projected load reflects the other athlete's plan count: B planned twice
        // as many sessions as A over the same window, so B's total projected load must be strictly
        // greater — if the two athletes' data were accidentally sharing state, this would either
        // be equal or reflect the wrong athlete's plans entirely.
        let totalLoadA = modelA.metrics.reduce(0) { $0 + $1.load }
        let totalLoadB = modelB.metrics.reduce(0) { $0 + $1.load }
        #expect(totalLoadA > 0)
        #expect(totalLoadB > totalLoadA)
    }
}

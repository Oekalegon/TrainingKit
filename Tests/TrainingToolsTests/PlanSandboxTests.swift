import Foundation
import Testing
import TrainingCore
@testable import TrainingTools

@Suite("PlanSandbox")
struct PlanSandboxTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func steadyWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    private func makeStores() async throws -> (InMemoryStore, StoreSet, AthleteProfile) {
        let store = InMemoryStore()
        let athlete = AthleteProfile.fixture()
        try await store.save(athlete)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, stores, athlete)
    }

    @Test("init throws without a saved athlete profile")
    func initThrowsWithoutAthlete() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        await #expect(throws: PlanSandboxError.missingAthleteProfile) {
            _ = try await PlanSandbox(snapshotOf: stores)
        }
    }

    @Test("snapshots the stores' current plans/workouts/cycles")
    func snapshotsStoreContents() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(1))
        try await store.upsert([workout])
        try await store.upsert([plan])

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(10))
        let plans = await sandbox.plans
        let workouts = await sandbox.workouts
        #expect(plans.map(\.id) == [plan.id])
        #expect(workouts.map(\.id) == [workout.id])
    }

    @Test("mutations don't touch the committed stores until commit(to:)")
    func mutationsStayInSandboxUntilCommit() async throws {
        let (store, stores, _) = try await makeStores()
        let sandbox = try await PlanSandbox(snapshotOf: stores)

        let workout = steadyWorkout()
        let plan = PlannedActivity(workoutID: workout.id, date: day(1))
        await sandbox.setWorkouts([workout])
        await sandbox.setPlans([plan])

        #expect(try await store.plans(in: day(0)...day(10)).isEmpty)

        try await sandbox.commit(to: stores)

        let committedPlans = try await store.plans(in: day(0)...day(10))
        #expect(committedPlans.map(\.id) == [plan.id])
    }

    @Test("commit(to:) deletes plans/workouts/cycles removed from the sandbox")
    func commitDeletesRemovedEntries() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        let keptPlan = PlannedActivity(workoutID: workout.id, date: day(1))
        let removedPlan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([workout])
        try await store.upsert([keptPlan, removedPlan])

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(10))
        await sandbox.setPlans([keptPlan])
        try await sandbox.commit(to: stores)

        let remainingPlans = try await store.plans(in: day(0)...day(10))
        #expect(remainingPlans.map(\.id) == [keptPlan.id])
        #expect(try await store.plan(id: removedPlan.id) == nil)
    }

    @Test("reset discards mutations back to the snapshot")
    func resetRestoresBaseline() async throws {
        let (_, stores, _) = try await makeStores()
        let sandbox = try await PlanSandbox(snapshotOf: stores)

        let plan = PlannedActivity(workoutID: UUID(), date: day(1))
        await sandbox.setPlans([plan])
        #expect(await sandbox.plans.count == 1)

        await sandbox.reset()
        #expect(await sandbox.plans.isEmpty)
    }

    @Test("diff reports added, removed, and modified entries by identity")
    func diffTracksChangesByIdentity() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        let keptPlan = PlannedActivity(workoutID: workout.id, date: day(1))
        let removedPlan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([workout])
        try await store.upsert([keptPlan, removedPlan])

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(10))
        var modifiedPlan = keptPlan
        modifiedPlan.date = day(3)
        let addedPlan = PlannedActivity(workoutID: workout.id, date: day(4))
        await sandbox.setWorkouts([workout])
        await sandbox.setPlans([modifiedPlan, addedPlan])

        let diff = await sandbox.diff()
        #expect(diff.plans.added.map(\.id) == [addedPlan.id])
        #expect(diff.plans.removed.map(\.id) == [removedPlan.id])
        #expect(diff.plans.modified.map(\.id) == [keptPlan.id])
    }

    @Test("simulate projects fitness metrics and evaluates them")
    func simulateProjectsAndEvaluates() async throws {
        let (store, stores, athlete) = try await makeStores()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        let sandbox = try await PlanSandbox(snapshotOf: stores)
        let plan = PlannedActivity(workoutID: workout.id, date: day(1))
        await sandbox.setWorkouts([workout])
        await sandbox.setPlans([plan])

        let result = await sandbox.simulate(
            engine: DefaultSeriesEngine(),
            evaluator: PlanEvaluator(),
            today: day(0)
        )

        #expect(!result.metrics.isEmpty)
        #expect(result.metrics.contains { $0.load > 0 })
        _ = athlete
    }

    @Test("simulate surfaces PlanEvaluator findings for a guardrail-tripping plan")
    func simulateSurfacesGuardrailFindings() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        // Beyond the default 42-day CTL warm-up, so the ramp rule actually evaluates (it skips
        // every `isWarmingUp` day by design, see `PlanEvaluator.ctlRampFindings`).
        let plans = (1...49).map { PlannedActivity(workoutID: workout.id, date: self.day($0)) }

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(60))
        await sandbox.setWorkouts([workout])
        await sandbox.setPlans(plans)

        let result = await sandbox.simulate(
            engine: DefaultSeriesEngine(),
            evaluator: PlanEvaluator(),
            today: day(0),
            guardrails: PlanGuardrails(maxCTLRampPerWeek: 0.01)
        )

        #expect(result.evaluation.findings.contains { $0.rule == .ctlRamp })
        #expect(!result.evaluation.isAcceptable)
    }
}

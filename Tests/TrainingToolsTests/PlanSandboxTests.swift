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
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, stores, athlete)
    }

    @Test("init throws without a saved athlete profile")
    func initThrowsWithoutAthlete() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
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

    @Test("an engine given races adds their load to the sandbox series")
    func engineWithRaces() {
        let athlete = AthleteProfile.fixture()
        let race = Race(name: "Race", date: day(3), priority: .primary, distanceMeters: 42_195)
        let without = DefaultSeriesEngine().metrics(activities: [], plans: [], workouts: [], races: [], athlete: athlete, today: day(0))
        let with = DefaultSeriesEngine().metrics(activities: [], plans: [], workouts: [], races: [race], athlete: athlete, today: day(0))

        #expect(without.allSatisfy { $0.load == 0 })
        #expect(with.contains { $0.load > 0 })
    }

    @Test("simulate adds the sandbox's races to the series it evaluates")
    func simulateAddsRaceLoad() async throws {
        let (_, stores, _) = try await makeStores()
        let race = Race(name: "Race", date: day(3), priority: .primary, distanceMeters: 42_195)

        let withRace = try await PlanSandbox(snapshotOf: stores, races: [race])
        let without = try await PlanSandbox(snapshotOf: stores)
        let engine = DefaultSeriesEngine()
        let a = await withRace.simulate(engine: engine, evaluator: PlanEvaluator(), today: day(0))
        let b = await without.simulate(engine: engine, evaluator: PlanEvaluator(), today: day(0))

        #expect(a.metrics.contains { $0.load > 0 })
        #expect(b.metrics.allSatisfy { $0.load == 0 })
    }

    @Test("simulate surfaces PlanEvaluator findings for a guardrail-tripping plan")
    func simulateSurfacesGuardrailFindings() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        try await store.upsert([workout])

        // Beyond the default 42-day CTL warm-up, so the TSB rule actually evaluates (it skips
        // every `isWarmingUp` day by design, see `PlanEvaluator.tsbBandFindings`).
        let plans = (1...49).map { PlannedActivity(workoutID: workout.id, date: self.day($0)) }

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(60))
        await sandbox.setWorkouts([workout])
        await sandbox.setPlans(plans)

        let result = await sandbox.simulate(
            engine: DefaultSeriesEngine(),
            evaluator: PlanEvaluator(),
            today: day(0),
            guardrails: PlanGuardrails(minAcceptableTSB: 0)
        )

        #expect(result.evaluation.findings.contains { $0.rule == .tsbBand })
        #expect(!result.evaluation.isAcceptable)
    }

    @Test("a snapshot holds only the active training plan's workouts, and commit puts new ones in it")
    func snapshotAndCommitFollowActivePlan() async throws {
        let store = InMemoryStore()
        try await store.save(AthleteProfile.fixture())
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, trainingPlanStore: store
        )
        let workout = steadyWorkout()
        try await store.upsert([workout])
        let active = TrainingPlan(name: "Now", status: .active), draft = TrainingPlan(name: "Alt")
        try await store.upsertTrainingPlan(active)
        try await store.upsertTrainingPlan(draft)
        let mine = PlannedActivity(workoutID: workout.id, date: day(1), planID: active.id)
        let theirs = PlannedActivity(workoutID: workout.id, date: day(2), planID: draft.id)
        try await store.upsert([mine, theirs])

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(10))
        #expect(await sandbox.plans.map(\.id) == [mine.id])

        let added = PlannedActivity(workoutID: workout.id, date: day(3))
        await sandbox.setPlans([mine, added])
        try await sandbox.commit(to: stores)

        #expect(try await store.plan(id: added.id)?.planID == active.id)
        #expect(try await store.plan(id: theirs.id) != nil) // the draft's workout isn't touched
    }

    @Test("commit refuses to delete a planned workout an activity has completed, before writing anything")
    func commitRefusesCompletedWorkoutRemoval() async throws {
        let (store, stores, _) = try await makeStores()
        let workout = steadyWorkout()
        try await store.upsert([workout])
        let done = PlannedActivity(workoutID: workout.id, date: day(1))
        let other = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([done, other])

        let sandbox = try await PlanSandbox(snapshotOf: stores, range: day(0)...day(10))
        await sandbox.setPlans([PlannedActivity(workoutID: workout.id, date: day(3))]) // removes both
        var completed = done
        completed.completedActivityID = UUID() // an import matched it after the snapshot
        try await store.upsert([completed])

        await #expect(throws: TrainingPlanError.workoutIsCompleted(done.id)) {
            try await sandbox.commit(to: stores)
        }
        #expect(try await store.plan(id: done.id) == completed)
        #expect(try await store.plan(id: other.id) == other)
    }
}

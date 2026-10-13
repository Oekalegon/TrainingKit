import Foundation
import Testing
@testable import TrainingCore

/// A ``PlanStore`` over an `InMemoryStore` whose reads can be made to fail.
private final class FlakyPlanStore: PlanStore, @unchecked Sendable {
    struct ReadFailure: Error {}
    let base: InMemoryStore
    var failsReads = false

    init(base: InMemoryStore) { self.base = base }

    func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
        if failsReads { throw ReadFailure() }
        return try await base.plans(in: range)
    }
    func upsert(_ plans: [PlannedActivity]) async throws { try await base.upsert(plans) }
    func plan(id: UUID) async throws -> PlannedActivity? { try await base.plan(id: id) }
    func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
}

/// The refined planned-load estimator is built once and kept until something changes (MVP2-160).
@MainActor
@Suite("TrainingModel refined estimator cache", .serialized)
struct RefinedEstimatorCacheTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func workout(minutes: Double, templateID: UUID? = nil) -> StructuredWorkout {
        StructuredWorkout(
            name: "W", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60), target: .heartRateZone(2))])],
            templateID: templateID
        )
    }

    private func makeModel() -> (InMemoryStore, FlakyPlanStore, TrainingModel) {
        let store = InMemoryStore()
        let plans = FlakyPlanStore(base: store)
        let stores = StoreSet(
            activityStore: store, planStore: plans, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, plans, TrainingModel(stores: stores, athlete: AthleteProfile.fixture()))
    }

    @Test("a second call reuses the first build")
    func secondCallIsCached() async throws {
        let (_, _, model) = makeModel()
        let before = model.refinedEstimatorBuildCount

        _ = await model.refinedEstimator()
        _ = try await model.loadRefinedEstimator()

        #expect(model.refinedEstimatorBuildCount == before + 1)
    }

    @Test("the recompute after a change builds it, so a host app's next call costs nothing")
    func recomputeSharesItsBuild() async throws {
        let (_, _, model) = makeModel()
        _ = await model.refinedEstimator()
        let afterFirst = model.refinedEstimatorBuildCount

        try await model.add(workout(minutes: 30), asOf: day(0))
        let afterChange = model.refinedEstimatorBuildCount
        _ = await model.refinedEstimator()
        _ = await model.refinedEstimator()

        #expect(afterChange == afterFirst + 1)
        #expect(model.refinedEstimatorBuildCount == afterChange)
    }

    @Test("a completed plan imported through the model shows up in the next call")
    func importInvalidates() async throws {
        let (store, _, model) = makeModel()
        let templateID = UUID()
        let done = workout(minutes: 30, templateID: templateID)
        let later = workout(minutes: 60, templateID: templateID)
        try await model.add(done, asOf: day(0))
        try await model.add(later, asOf: day(0))
        let plan = PlannedActivity(workoutID: done.id, date: day(0))
        try await model.add(plan, asOf: day(0))
        try await model.load(in: day(0)...day(1), asOf: day(0))
        let base = TRIMPPlanEstimator().estimatedLoad(for: later, athlete: model.athlete)
        let unrefined = await model.refinedEstimator().estimatedLoad(for: later, athlete: model.athlete)
        #expect(unrefined == base)

        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800, importedLoad: 50)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(0))
        #expect(try await store.plan(id: plan.id)?.completedActivityID == activity.id)

        let refined = await model.refinedEstimator().estimatedLoad(for: later, athlete: model.athlete)
        #expect(refined.value != base.value)
    }

    @Test("concurrent callers share one build")
    func concurrentCallersShare() async throws {
        let (_, _, model) = makeModel()
        let before = model.refinedEstimatorBuildCount

        async let first = model.loadRefinedEstimator()
        async let second = model.loadRefinedEstimator()
        _ = try await (first, second)

        #expect(model.refinedEstimatorBuildCount == before + 1)
    }

    @Test("an invalidation makes the next call read the stores again")
    func invalidationRebuilds() async throws {
        let (_, _, model) = makeModel()
        _ = await model.refinedEstimator()
        let before = model.refinedEstimatorBuildCount

        model.invalidateRefinedEstimator()
        _ = await model.refinedEstimator()

        #expect(model.refinedEstimatorBuildCount == before + 1)
    }

    @Test("a failed read throws from the throwing variant, falls back from the other, and isn't kept")
    func failureIsNotKept() async throws {
        let (_, plans, model) = makeModel()
        model.invalidateRefinedEstimator()
        plans.failsReads = true

        await #expect(throws: FlakyPlanStore.ReadFailure.self) { try await model.loadRefinedEstimator() }
        let fallback = await model.refinedEstimator()
        let workout = workout(minutes: 30)
        #expect(
            fallback.estimatedLoad(for: workout, athlete: model.athlete)
                == TRIMPPlanEstimator().estimatedLoad(for: workout, athlete: model.athlete)
        )

        plans.failsReads = false
        _ = try await model.loadRefinedEstimator()
        let afterRecovery = model.refinedEstimatorBuildCount
        _ = try await model.loadRefinedEstimator()

        #expect(model.refinedEstimatorBuildCount == afterRecovery)
    }
}

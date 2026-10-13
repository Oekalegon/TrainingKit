import Foundation
import Testing
@testable import TrainingCore
@testable import TrainingPersistence

/// What the refined planned-load estimator costs on a store with a long history, and what the cache saves
/// (MVP2-160). Prints the timings; asserts only that a kept estimator is much cheaper than a build.
@MainActor
@Suite("Refined estimator on a large store (MVP2-160)", .serialized)
struct RefinedEstimatorLargeStoreTests {
    /// Completed one-hour runs, each a plan linked to an activity with a heart-rate sample every 5 s.
    private static let completedRuns = 400

    @Test("a kept estimator costs next to nothing; a build reads and scores the whole history")
    func timings() async throws {
        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)

        let templateID = UUID()
        let workout = StructuredWorkout(
            name: "Easy", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(2))])],
            templateID: templateID
        )
        try await store.upsert([workout])
        let origin = Date(timeIntervalSince1970: 1_600_000_000)
        var plans: [PlannedActivity] = []
        var activities: [Activity] = []
        for index in 0..<Self.completedRuns {
            let start = origin.addingTimeInterval(Double(index) * 86_400)
            let samples = stride(from: 0.0, through: 3600, by: 5).map {
                HeartRateSample(time: start.addingTimeInterval($0), bpm: 140 + Double(Int($0) % 20))
            }
            var activity = Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 3600, heartRate: samples)
            var plan = PlannedActivity(workoutID: workout.id, date: start)
            activity.linkedPlanID = plan.id
            plan.completedActivityID = activity.id
            plans.append(plan)
            activities.append(activity)
        }
        try await store.upsert(activities)
        try await store.upsert(plans)
        // Loading recomputes, which builds the estimator once, as an import would.
        let recompute = try await ContinuousClock().measure {
            try await model.load(in: origin...origin.addingTimeInterval(86_400), asOf: origin.addingTimeInterval(86_400))
        }
        model.invalidateRefinedEstimator()

        let clock = ContinuousClock()
        var built: any PlannedLoadEstimator = TRIMPPlanEstimator()
        let build = try await clock.measure { built = try await model.loadRefinedEstimator() }
        let kept = try await clock.measure { _ = try await model.loadRefinedEstimator() }
        let refined = try #require(built as? LinkedActivityRefinedEstimator)

        print("""
        REFINED-ESTIMATOR TIMINGS (\(Self.completedRuns) completed 1 h runs, 720 heart-rate samples each, SwiftData in memory)
          build (read + score everything): \(build)
          kept estimator:                  \(kept)
          load + recompute (builds it once): \(recompute)
          references scored:               \(refined.references.count)
        """)
        #expect(refined.references.count == Self.completedRuns)
        #expect(kept < build / 20)
    }
}

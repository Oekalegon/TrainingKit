import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel intensity", .serialized)
struct TrainingModelIntensityTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func makeModel(intensityParameters: IntensityClassifierParameters = IntensityClassifierParameters()) -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return TrainingModel(stores: stores, athlete: AthleteProfile.fixture(), intensityParameters: intensityParameters)
    }

    private func step(_ kind: StepKind, seconds: Double, zone: Int) -> WorkoutStep {
        WorkoutStep(kind: kind, goal: .time(seconds), target: .heartRateZone(zone))
    }

    /// 10 min warm-up, 16 × (30 s at zone 5, 60 s at zone 1), 10 min cool-down: 8 minutes of hard work in
    /// reps too short for heart rate alone to recognise.
    private var shortRepWorkout: StructuredWorkout {
        StructuredWorkout(name: "16×30s", sport: .running, blocks: [
            WorkoutBlock(steps: [step(.warmup, seconds: 600, zone: 1)]),
            WorkoutBlock(steps: [step(.work, seconds: 30, zone: 5), step(.recovery, seconds: 60, zone: 1)], repetitions: 16),
            WorkoutBlock(steps: [step(.cooldown, seconds: 600, zone: 1)]),
        ])
    }

    private var shortRepProfile: [SimulatedHeartRate.Effort] {
        var profile: [SimulatedHeartRate.Effort] = [(600, 130)]
        for _ in 0..<16 {
            profile += [(30, 186), (60, 125)]
        }
        profile.append((600, 125))
        return profile
    }

    private func shortRepActivity() -> Activity {
        Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 2640,
            heartRate: SimulatedHeartRate.samples(shortRepProfile, start: start)
        )
    }

    @Test("an activity with no linked plan is classified from its heart rate alone")
    func unlinkedActivityIsMeasured() async throws {
        let model = makeModel()
        let easyRun = Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 3600,
            heartRate: SimulatedHeartRate.samples([(3600, 140)], start: start)
        )

        let result = try #require(model.intensity(of: easyRun))

        #expect(result.category == .low)
        #expect(result.source == .measured)
    }

    @Test("an activity linked to a loaded plan is classified against the plan")
    func linkedActivityIsPlanGuided() async throws {
        let model = makeModel()
        let workout = shortRepWorkout
        try await model.add(workout, asOf: start)
        let plan = PlannedActivity(workoutID: workout.id, date: start)
        try await model.add(plan, asOf: start)
        try await model.load(in: start...start.addingTimeInterval(86_400), asOf: start)
        try await model.importActivities(from: StubImporter(activities: [shortRepActivity()]), asOf: start)

        let activity = try #require(model.activities.first)
        #expect(activity.linkedPlanID == plan.id)

        let guided = try #require(model.intensity(of: activity))
        var unlinked = activity
        unlinked.linkedPlanID = nil
        let heartRateOnly = try #require(model.intensity(of: unlinked))

        #expect(guided.category == .high)
        #expect(guided.source == .blended)
        #expect(heartRateOnly.category < .high)
    }

    @Test("a linked activity whose plan's workout isn't loaded falls back to heart rate alone")
    func missingWorkoutFallsBack() async throws {
        let model = makeModel()
        let orphanPlan = PlannedActivity(workoutID: UUID(), date: start)
        try await model.add(orphanPlan, asOf: start)
        try await model.load(in: start...start.addingTimeInterval(86_400), asOf: start)
        var activity = shortRepActivity()
        activity.linkedPlanID = orphanPlan.id

        #expect(model.intensity(of: activity)?.source == .measured)
        #expect(model.intensity(of: orphanPlan) == nil)
    }

    @Test("a plan's intensity comes from its workout, independent of completion")
    func planIntensity() async throws {
        let model = makeModel()
        let workout = shortRepWorkout
        try await model.add(workout, asOf: start)
        let plan = PlannedActivity(workoutID: workout.id, date: start)
        try await model.add(plan, asOf: start)

        let result = try #require(model.intensity(of: plan))

        #expect(result.category == .high)
        #expect(result.source == .planned)
    }

    @Test("intensityParameters are used, and changes apply to the next call")
    func parametersApply() async throws {
        let model = makeModel(intensityParameters: IntensityClassifierParameters(highMinimumSeconds: 3600))
        let workout = shortRepWorkout
        try await model.add(workout, asOf: start)
        let plan = PlannedActivity(workoutID: workout.id, date: start)
        try await model.add(plan, asOf: start)

        #expect(model.intensity(of: plan)?.category == .medium)

        model.intensityParameters = IntensityClassifierParameters()

        #expect(model.intensity(of: plan)?.category == .high)
    }

    @Test("a linked plan outside the loaded range isn't available, so the activity falls back to heart rate alone")
    func linkedPlanOutsideLoadedRange() async throws {
        let model = makeModel()
        let workout = shortRepWorkout
        try await model.add(workout, asOf: start)
        let plan = PlannedActivity(workoutID: workout.id, date: start)
        try await model.add(plan, asOf: start)
        // Load a window that doesn't include the plan's day.
        let later = start.addingTimeInterval(20 * 86_400)
        try await model.load(in: later...later.addingTimeInterval(86_400), asOf: later)
        #expect(!model.plans.contains { $0.id == plan.id })

        var activity = shortRepActivity()
        activity.linkedPlanID = plan.id

        #expect(model.intensity(of: activity)?.source == .measured)
    }
}

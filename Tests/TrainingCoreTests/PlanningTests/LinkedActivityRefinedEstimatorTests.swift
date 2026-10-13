import Foundation
import Testing
@testable import TrainingCore

@Suite("LinkedActivityRefinedEstimator")
struct LinkedActivityRefinedEstimatorTests {
    let athlete = AthleteProfile.fixture()
    let base = TRIMPPlanEstimator()
    let template = WorkoutTemplate(
        name: "Steady run",
        sport: .running,
        parameters: [WorkoutTemplateParameter(key: "duration", name: "Duration", unit: .minutes, defaultValue: 30 * 60)],
        blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(2))])]
    )

    private func workout(minutes: Double) throws -> StructuredWorkout {
        try template.instantiate(values: ["duration": minutes * 60])
    }

    @Test("without references the base estimate is returned unchanged")
    func noReferences() throws {
        let target = try workout(minutes: 30)
        let refined = LinkedActivityRefinedEstimator(references: [])
        #expect(refined.estimatedLoad(for: target, athlete: athlete) == base.estimatedLoad(for: target, athlete: athlete))
    }

    @Test("the same workout done once takes the actual load")
    func sameWorkoutTakesActual() throws {
        let target = try workout(minutes: 30)
        let refined = LinkedActivityRefinedEstimator(references: [.init(workout: target, actualLoad: 42)])
        let load = refined.estimatedLoad(for: target, athlete: athlete)
        #expect(abs(load.value - 42) < 1e-9)
        #expect(load.method == .estimatedFromPlan)
        #expect(load.confidence > base.estimatedLoad(for: target, athlete: athlete).confidence)
    }

    @Test("several runs of the same workout give the median actual load")
    func medianOfRuns() throws {
        let target = try workout(minutes: 30)
        let refined = LinkedActivityRefinedEstimator(references: [10, 40, 1000].map { .init(workout: target, actualLoad: $0) })
        #expect(abs(refined.estimatedLoad(for: target, athlete: athlete).value - 40) < 1e-9)
    }

    @Test("a more recent run weighs more than an older one")
    func recentWeighsMore() throws {
        let target = try workout(minutes: 30)
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let refined = LinkedActivityRefinedEstimator(references: [
            .init(workout: target, actualLoad: 20, date: start),
            .init(workout: target, actualLoad: 30, date: start.addingTimeInterval(day)),
            .init(workout: target, actualLoad: 60, date: start.addingTimeInterval(400 * day)),
        ])
        // The 400-day-newer run dominates, so the plain median (30) is beaten.
        #expect(abs(refined.estimatedLoad(for: target, athlete: athlete).value - 60) < 1e-9)
        #expect(LinkedActivityRefinedEstimator.weightedMedian([(1, 1), (3, 1)]) == 2)
        #expect(LinkedActivityRefinedEstimator.weightedMedian([(1, 1), (2, 1), (9, 1)]) == 2)
    }

    @Test("a run with other template parameters is scaled by the estimates, not used raw")
    func scaledByParameters() throws {
        let done = try workout(minutes: 30)
        let target = try workout(minutes: 60)
        let refined = LinkedActivityRefinedEstimator(references: [.init(workout: done, actualLoad: 40)])
        let doneEstimate = base.estimatedLoad(for: done, athlete: athlete).value
        let targetEstimate = base.estimatedLoad(for: target, athlete: athlete).value
        #expect(abs(refined.estimatedLoad(for: target, athlete: athlete).value - 40 * targetEstimate / doneEstimate) < 1e-9)
    }

    @Test("the scaling follows the zone a step is in, not just its duration")
    func scaledByZone() throws {
        let easy = StructuredWorkout(
            name: "Easy", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])],
            templateID: UUID()
        )
        var hard = easy
        hard.blocks = [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(4))])]
        let refined = LinkedActivityRefinedEstimator(references: [.init(workout: easy, actualLoad: 30)])
        let baseEasy = base.estimatedLoad(for: easy, athlete: athlete).value
        let baseHard = base.estimatedLoad(for: hard, athlete: athlete).value
        // The athlete scored 30 where the base said `baseEasy`; the same correction applies to the zone 4 version.
        #expect(abs(refined.estimatedLoad(for: hard, athlete: athlete).value - 30 * baseHard / baseEasy) < 1e-9)
        #expect(baseHard > baseEasy)
    }

    @Test("a different workout, and one with no template, isn't refined")
    func unrelatedWorkoutsIgnored() throws {
        let other = StructuredWorkout(
            name: "Other", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let target = try workout(minutes: 30)
        let refined = LinkedActivityRefinedEstimator(references: [.init(workout: other, actualLoad: 99)])
        #expect(refined.estimatedLoad(for: target, athlete: athlete) == base.estimatedLoad(for: target, athlete: athlete))
    }

    @Test("non-positive actual loads are ignored")
    func zeroLoadIgnored() throws {
        let target = try workout(minutes: 30)
        let refined = LinkedActivityRefinedEstimator(references: [.init(workout: target, actualLoad: 0)])
        #expect(refined.references.isEmpty)
        #expect(refined.estimatedLoad(for: target, athlete: athlete) == base.estimatedLoad(for: target, athlete: athlete))
    }

    @Test("confidence grows with each reference and stays below 1")
    func confidenceCurve() {
        #expect(abs(LinkedActivityRefinedEstimator.confidence(base: 0.7, references: 1) - 0.85) < 1e-9)
        #expect(abs(LinkedActivityRefinedEstimator.confidence(base: 0.7, references: 2) - 0.925) < 1e-9)
        #expect(LinkedActivityRefinedEstimator.confidence(base: 0.7, references: 20) == 0.95)
        #expect(LinkedActivityRefinedEstimator.confidence(base: 0.99, references: 1) == 0.99)
    }

    @Test("a run stopped far short of the workout is skipped")
    func partialRunSkipped() throws {
        let target = try workout(minutes: 60)
        let partial = LinkedActivityRefinedEstimator(references: [.init(workout: target, actualLoad: 8, actualDuration: 10 * 60)])
        #expect(partial.estimatedLoad(for: target, athlete: athlete) == base.estimatedLoad(for: target, athlete: athlete))
        let full = LinkedActivityRefinedEstimator(references: [.init(workout: target, actualLoad: 40, actualDuration: 58 * 60)])
        #expect(abs(full.estimatedLoad(for: target, athlete: athlete).value - 40) < 1e-9)
    }

    @Test("excluding references from a cutoff keeps a plan's own activity out of its estimate")
    func cutoffExcludesOwnActivity() throws {
        let target = try workout(minutes: 30)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let own = earlier.addingTimeInterval(86_400)
        let refined = LinkedActivityRefinedEstimator(references: [
            .init(workout: target, actualLoad: 30, date: earlier),
            .init(workout: target, actualLoad: 90, date: own),
        ])
        #expect(refined.estimatedLoad(for: target, athlete: athlete).value > 30)
        let before = refined.excludingReferences(onOrAfter: own)
        #expect(abs(before.estimatedLoad(for: target, athlete: athlete).value - 30) < 1e-9)
        #expect(before.excludingReferences(onOrAfter: earlier).estimatedLoad(for: target, athlete: athlete)
                == base.estimatedLoad(for: target, athlete: athlete))
    }

    @Test("a non-positive half-life weighs only the newest run; no zone settings keeps the zero estimate")
    func degenerateInputs() throws {
        let target = try workout(minutes: 30)
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let refined = LinkedActivityRefinedEstimator(references: [
            .init(workout: target, actualLoad: 20, date: start),
            .init(workout: target, actualLoad: 70, date: start.addingTimeInterval(day)),
        ], halfLife: 0)
        #expect(abs(refined.estimatedLoad(for: target, athlete: athlete).value - 70) < 1e-9)

        var bare = athlete
        bare.heartRateZoneHistory = []
        let zero = refined.estimatedLoad(for: target, athlete: bare)
        #expect(zero.value == 0 && zero.confidence == 0)
    }
}

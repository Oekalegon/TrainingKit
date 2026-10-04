import Foundation
import Testing
@testable import TrainingCore

@Suite("BuiltInWorkoutTemplates")
struct BuiltInWorkoutTemplatesTests {
    @Test("recovery run instantiates as a single Zone 1 block at the requested duration")
    func recoveryRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.recoveryRun.instantiate(values: ["duration": 25 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(25 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("easy run instantiates with fixed warmup/cooldown and a variable Zone 2 main block")
    func easyRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(values: ["duration": 40 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(40 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("long run instantiates with fixed warmup/cooldown and a variable Zone 2 main distance")
    func longRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.longRun.instantiate(values: ["distance": 28_000])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(28_000), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("tempo run instantiates with only the true edges as warmup/cooldown, matching what WorkoutKitBridge extracts")
    func tempoRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.tempoRun.instantiate(values: ["duration": 20 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(20 * 60), target: .heartRateZone(3))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .recovery, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("base full-out hill sprints: warmup, open Zone 2 run, N × (8 s all-out, Zone 1 rest), open Zone 2 run, cooldown")
    func baseHillSprintsInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.baseHillSprints.instantiate(values: ["reps": 8, "rest": 4 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(8), target: .rpe(10)),
                    WorkoutStep(kind: .recovery, goal: .time(4 * 60), target: .heartRateZone(1)),
                ],
                repetitions: 8
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("base full-out hill sprints default to 6 sprints with 5 minutes' rest, and offer 3–12 sprints and 3–15 minutes' rest")
    func baseHillSprintsDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.baseHillSprints
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 6)
        #expect(workout.blocks[2].steps[1].goal == .time(300))
        let reps = try #require(template.parameters.first { $0.key == "reps" })
        let rest = try #require(template.parameters.first { $0.key == "rest" })
        #expect(reps.range == 3...12)
        #expect(rest.range == 180...900)
    }

    @Test("short interval run: warmup, Zone 2 ramp-in, N × (Zone 5 effort, Zone 1 recovery), cooldown")
    func shortIntervalRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate(values: ["reps": 10, "work": 45, "rest": 120])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(45), target: .heartRateZone(5)),
                    WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(1)),
                ],
                repetitions: 10
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("short interval run defaults to 8 × 1 min with 90 s recovery, and offers 6–12 reps, 30–120 s efforts, 60–180 s recoveries")
    func shortIntervalRunDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.shortIntervalRun
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 8)
        #expect(workout.blocks[2].steps.map(\.goal) == [.time(60), .time(90)])
        func range(_ key: String) throws -> ClosedRange<Double>? { try #require(template.parameters.first { $0.key == key }).range }
        #expect(try range("reps") == 6...12)
        #expect(try range("work") == 30...120)
        #expect(try range("rest") == 60...180)
    }

    @Test("short interval run (track): N × (Zone 5 distance, Zone 2 recovery) between the warmup and cooldown")
    func shortIntervalRunTrackInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRunTrack.instantiate(values: ["reps": 6, "distance": 200, "rest": 75])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .distance(200), target: .heartRateZone(5)),
                    WorkoutStep(kind: .recovery, goal: .time(75), target: .heartRateZone(2)),
                ],
                repetitions: 6
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("short interval run (track) defaults to 8 × 400 m with 90 s recovery, and offers 6–12 reps, 50–800 m efforts, 60–180 s recoveries")
    func shortIntervalRunTrackDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.shortIntervalRunTrack
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 8)
        #expect(workout.blocks[2].steps.map(\.goal) == [.distance(400), .time(90)])
        func range(_ key: String) throws -> ClosedRange<Double>? { try #require(template.parameters.first { $0.key == key }).range }
        #expect(try range("reps") == 6...12)
        #expect(try range("distance") == 50...800)
        #expect(try range("rest") == 60...180)
    }

    @Test("the interval templates plan a duration from their steps, counting each open step as 10 minutes")
    func intervalTemplatesPlannedDuration() throws {
        let athlete = AthleteProfile.fixture()
        let estimator = WorkoutDurationEstimator()

        let hills = try BuiltInWorkoutTemplates.baseHillSprints.instantiate()
        // 5 min warmup + open run + 6 × (8 s sprint + 5 min rest) + open run + 5 min cooldown.
        let hillRepetition: TimeInterval = 8 + 300
        let expectedHills: TimeInterval = 300 + 600 + 6 * hillRepetition + 600 + 300
        #expect(estimator.duration(for: hills, athlete: athlete) == expectedHills)

        let short = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()
        // 5 + 5 min, 8 × (60 s + 90 s), 5 min cooldown.
        let shortRepetition: TimeInterval = 60 + 90
        let expectedShort: TimeInterval = 300 + 300 + 8 * shortRepetition + 300
        #expect(estimator.duration(for: short, athlete: athlete) == expectedShort)
    }

    @Test("every built-in template has a positive estimated load with its default parameters")
    func builtInsHavePositiveLoad() throws {
        let athlete = AthleteProfile.fixture()

        for template in BuiltInWorkoutTemplates.all {
            let load = try template.expectedLoad(estimator: TRIMPPlanEstimator(), athlete: athlete)
            #expect(load.value > 0, "\(template.name)")
        }
    }

    @Test("built-in templates have distinct, stable ids")
    func builtInsHaveDistinctIDs() {
        let ids = Set(BuiltInWorkoutTemplates.all.map(\.id))

        #expect(ids.count == BuiltInWorkoutTemplates.all.count)
    }
}

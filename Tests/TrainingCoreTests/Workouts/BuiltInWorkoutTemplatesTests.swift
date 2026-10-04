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

    @Test("built-in templates have distinct, stable ids")
    func builtInsHaveDistinctIDs() {
        let ids = Set(BuiltInWorkoutTemplates.all.map(\.id))

        #expect(ids.count == BuiltInWorkoutTemplates.all.count)
    }
}

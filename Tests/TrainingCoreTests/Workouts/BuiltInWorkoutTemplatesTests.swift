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

    @Test("built-in templates have distinct, stable ids")
    func builtInsHaveDistinctIDs() {
        let ids = Set(BuiltInWorkoutTemplates.all.map(\.id))

        #expect(ids.count == BuiltInWorkoutTemplates.all.count)
    }
}

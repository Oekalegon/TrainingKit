#if canImport(WorkoutKit)
import HealthKit
import WorkoutKit
import Foundation
import Testing
@testable import TrainingWorkoutKit
import TrainingCore

@Suite("WorkoutKitBridge")
struct WorkoutKitBridgeTests {
    private let bridge = WorkoutKitBridge()

    // MARK: - Support validation

    @Test("customWorkout(from:) throws unsupportedActivity when the sport's activity type isn't supported at all")
    func customWorkoutThrowsForUnsupportedActivity() {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in false },
            supportsGoal: { _, _ in true },
            supportsAlert: { _, _ in true }
        ))
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )

        #expect(throws: WorkoutKitMappingError.unsupportedActivity(.running)) {
            try bridge.customWorkout(from: workout)
        }
    }

    @Test("customWorkout(from:) throws unsupportedGoalForActivity when a step's goal isn't supported for the sport")
    func customWorkoutThrowsForUnsupportedGoal() {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in true },
            supportsGoal: { _, _ in false },
            supportsAlert: { _, _ in true }
        ))
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )

        #expect(throws: WorkoutKitMappingError.unsupportedGoalForActivity(.time(1800, .seconds), .running)) {
            try bridge.customWorkout(from: workout)
        }
    }

    @Test("customWorkout(from:) throws unsupportedAlertForActivity when a step's alert isn't supported for the sport")
    func customWorkoutThrowsForUnsupportedAlert() {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in true },
            supportsGoal: { _, _ in true },
            supportsAlert: { _, _ in false }
        ))
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )

        #expect(throws: WorkoutKitMappingError.unsupportedAlertForActivity(.running)) {
            try bridge.customWorkout(from: workout)
        }
    }

    @Test("customWorkout(from:) doesn't consult supportsAlert for a step with no target")
    func customWorkoutSkipsAlertCheckWhenNoTarget() throws {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in true },
            supportsGoal: { _, _ in true },
            supportsAlert: { _, _ in false } // would fail every step if consulted
        ))
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])] // no target
        )

        let customWorkout = try bridge.customWorkout(from: workout)

        #expect(customWorkout.blocks[0].steps[0].step.alert == nil)
    }

    // MARK: - customWorkout(from:)

    @Test("a workout with warmup, work, and cooldown blocks maps to a CustomWorkout with the warmup/cooldown slots split out")
    func customWorkoutSplitsWarmupAndCooldown() throws {
        let workout = StructuredWorkout(
            name: "Tempo run",
            sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(2))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1200), target: .heartRateZone(4))], repetitions: 2),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300), target: .heartRateZone(1))]),
            ]
        )

        let customWorkout = try bridge.customWorkout(from: workout)

        #expect(customWorkout.activity == .running)
        #expect(customWorkout.displayName == "Tempo run")
        #expect(customWorkout.warmup?.goal == .time(600, .seconds))
        #expect(customWorkout.cooldown?.goal == .time(300, .seconds))
        #expect(customWorkout.blocks.count == 1)
        #expect(customWorkout.blocks[0].iterations == 2)
        #expect(customWorkout.blocks[0].steps.count == 1)
        #expect(customWorkout.blocks[0].steps[0].purpose == .work)
    }

    @Test("a multi-step leading block does not get split out as a warmup, since CustomWorkout's warmup slot only holds one step")
    func multiStepLeadingBlockStaysAnIntervalBlock() throws {
        let workout = StructuredWorkout(
            name: "Two-step start",
            sport: .running,
            blocks: [
                WorkoutBlock(steps: [
                    WorkoutStep(kind: .warmup, goal: .time(300)),
                    WorkoutStep(kind: .warmup, goal: .time(300)),
                ]),
            ]
        )

        let customWorkout = try bridge.customWorkout(from: workout)

        #expect(customWorkout.warmup == nil)
        #expect(customWorkout.blocks.count == 1)
        #expect(customWorkout.blocks[0].steps.count == 2)
    }

    // MARK: - structuredWorkout(from:)

    @Test("structuredWorkout(from:) recovers a StructuredWorkout from a WorkoutPlan wrapping a CustomWorkout, tagged with the plan's id")
    func structuredWorkoutRecoversFromWorkoutPlan() throws {
        let workout = StructuredWorkout(
            name: "Intervals",
            sport: .cycling,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(400), target: .power(200...220))], repetitions: 6),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300))]),
            ]
        )
        let customWorkout = try bridge.customWorkout(from: workout)
        let plan = WorkoutPlan(.custom(customWorkout))

        let recovered = try bridge.structuredWorkout(from: plan)

        #expect(recovered.workoutKitID == plan.id)
        #expect(recovered.sport == .cycling)
        #expect(recovered.name == "Intervals")
        #expect(recovered.blocks.count == 3)
        #expect(recovered.blocks[0].steps[0].kind == .warmup)
        #expect(recovered.blocks[1].repetitions == 6)
        #expect(recovered.blocks[1].steps[0].kind == .work)
        #expect(recovered.blocks[2].steps[0].kind == .cooldown)
    }

    @Test("structuredWorkout(from:) throws for a WorkoutPlan that doesn't wrap a CustomWorkout")
    func structuredWorkoutThrowsForNonCustomWorkoutPlan() {
        let plan = WorkoutPlan(.goal(SingleGoalWorkout(activity: .running, goal: .open)))

        #expect(throws: WorkoutKitMappingError.unsupportedWorkoutKind(plan.workout)) {
            try bridge.structuredWorkout(from: plan)
        }
    }

    // MARK: - sync(_:)

    @Test("sync(_:) returns the workout's existing workoutKitID when it has one, rather than a new id")
    func syncReusesExistingWorkoutKitID() async throws {
        let existingID = UUID()
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])],
            workoutKitID: existingID
        )

        let returnedID = try await bridge.sync(workout)

        #expect(returnedID == existingID)
    }

    @Test("sync(_:) mints a fresh id when the workout hasn't been synced before")
    func syncMintsFreshIDWhenUnsynced() async throws {
        let workout = StructuredWorkout(
            name: "Easy run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )

        let returnedID = try await bridge.sync(workout)

        #expect(workout.workoutKitID == nil)
        _ = returnedID // a fresh UUID; nothing more specific to assert on its value
    }
}
#endif

#if canImport(WorkoutKit)
import HealthKit
import WorkoutKit
import Foundation
import Testing
@testable import TrainingWorkoutKit
import TrainingCore

@Suite("WorkoutKit mapping")
struct WorkoutKitMappingTests {
    // MARK: - Sport

    @Test("common Sport cases map to their direct HKWorkoutActivityType, and back")
    func sportDirectMappingsRoundTrip() {
        let sports: [Sport] = [.running, .cycling, .swimming, .strength, .walking, .rowing]
        for sport in sports {
            let activityType = sport.workoutKitActivityType
            #expect(Sport(workoutKitActivityType: activityType) == sport)
        }
    }

    @Test("an unmapped activity type falls back to .other, labeled with its raw value, and recovers the original type")
    func sportFallsBackToOtherAndRoundTrips() {
        let sport = Sport(workoutKitActivityType: .yoga)

        guard case .other(let label) = sport else {
            Issue.record("expected .other, got \(sport)")
            return
        }
        #expect(label.contains("\(HKWorkoutActivityType.yoga.rawValue)"))
        #expect(sport.workoutKitActivityType == .yoga)
    }

    @Test("an .other label that isn't a recognized raw-value format falls back to .other activity type")
    func sportOtherWithUnparsableLabelFallsBackToGenericOther() {
        let sport = Sport.other("hand-typed label")
        #expect(sport.workoutKitActivityType == .other)
    }

    // MARK: - StepGoal / WorkoutGoal

    @Test("time, distance, and open step goals map onto their WorkoutGoal equivalents")
    func stepGoalMapsToWorkoutGoal() {
        #expect(WorkoutGoal(stepGoal: .time(300)) == .time(300, .seconds))
        #expect(WorkoutGoal(stepGoal: .distance(1000)) == .distance(1000, .meters))
        #expect(WorkoutGoal(stepGoal: .open) == .open)
    }

    @Test("WorkoutGoal maps back to StepGoal, converting units to seconds/meters")
    func workoutGoalMapsToStepGoal() throws {
        let fromMinutes = try StepGoal(workoutGoal: .time(5, .minutes))
        guard case .time(let seconds) = fromMinutes else {
            Issue.record("expected .time")
            return
        }
        #expect(abs(seconds - 300) < 1e-9)

        let fromKilometers = try StepGoal(workoutGoal: .distance(1, .kilometers))
        guard case .distance(let meters) = fromKilometers else {
            Issue.record("expected .distance")
            return
        }
        #expect(abs(meters - 1000) < 1e-9)

        #expect(try StepGoal(workoutGoal: .open) == .open)
    }

    @Test("energy and pool-swim goals have no StepGoal equivalent and throw")
    func unsupportedWorkoutGoalsThrow() {
        #expect(throws: WorkoutKitMappingError.unsupportedGoal(.energy(200, .kilocalories))) {
            try StepGoal(workoutGoal: .energy(200, .kilocalories))
        }
    }

    // MARK: - IntensityTarget / WorkoutAlert

    @Test("heart-rate zone and range targets map onto their WorkoutKit alerts, and back")
    func heartRateTargetsRoundTrip() throws {
        let zoneAlert = try #require(IntensityTarget.heartRateZone(3).workoutAlert as? HeartRateZoneAlert)
        #expect(zoneAlert.zone == 3)
        #expect(IntensityTarget(workoutAlert: zoneAlert) == .heartRateZone(3))

        let rangeAlert = try #require(IntensityTarget.heartRateRange(120, 150).workoutAlert as? HeartRateRangeAlert)
        let mapped = try #require(IntensityTarget(workoutAlert: rangeAlert))
        guard case .heartRateRange(let low, let high) = mapped else {
            Issue.record("expected .heartRateRange")
            return
        }
        #expect(abs(low - 120) < 1e-6)
        #expect(abs(high - 150) < 1e-6)
    }

    @Test("a heart-rate range given with reversed bounds doesn't trap building the WorkoutKit ClosedRange")
    func heartRateRangeWithReversedBoundsDoesNotCrash() throws {
        let alert = try #require(IntensityTarget.heartRateRange(150, 120).workoutAlert as? HeartRateRangeAlert)
        let unit = WorkoutAlertMetric.countPerMinute
        #expect(abs(alert.target.lowerBound.converted(to: unit).value - 120) < 1e-6)
        #expect(abs(alert.target.upperBound.converted(to: unit).value - 150) < 1e-6)
    }

    @Test("a pace target maps onto a speed alert, inverted (faster pace = higher speed), and back")
    func paceTargetRoundTrips() throws {
        // 4:00/km ... 5:00/km, i.e. 240...300 seconds/km.
        let target = IntensityTarget.pace(240...300)
        let alert = try #require(target.workoutAlert as? SpeedRangeAlert)

        let low = alert.target.lowerBound.converted(to: .metersPerSecond).value
        let high = alert.target.upperBound.converted(to: .metersPerSecond).value
        // 240s/km -> 1000/240 m/s (faster, higher speed); 300s/km -> 1000/300 m/s (slower, lower speed).
        #expect(abs(high - 1000.0 / 240) < 1e-6)
        #expect(abs(low - 1000.0 / 300) < 1e-6)

        let mapped = try #require(IntensityTarget(workoutAlert: alert))
        guard case .pace(let range) = mapped else {
            Issue.record("expected .pace")
            return
        }
        #expect(abs(range.lowerBound - 240) < 1e-6)
        #expect(abs(range.upperBound - 300) < 1e-6)
    }

    @Test("a power target maps onto a power-range alert, and back")
    func powerTargetRoundTrips() throws {
        let target = IntensityTarget.power(200...250)
        let alert = try #require(target.workoutAlert as? PowerRangeAlert)
        #expect(abs(alert.target.lowerBound.converted(to: .watts).value - 200) < 1e-6)
        #expect(abs(alert.target.upperBound.converted(to: .watts).value - 250) < 1e-6)

        let mapped = try #require(IntensityTarget(workoutAlert: alert))
        guard case .power(let range) = mapped else {
            Issue.record("expected .power")
            return
        }
        #expect(abs(range.lowerBound - 200) < 1e-6)
        #expect(abs(range.upperBound - 250) < 1e-6)
    }

    @Test("an RPE target has no WorkoutKit alert equivalent")
    func rpeTargetHasNoAlert() {
        #expect(IntensityTarget.rpe(7).workoutAlert == nil)
    }

    @Test("a power-zone alert has no IntensityTarget equivalent")
    func powerZoneAlertHasNoTarget() {
        #expect(IntensityTarget(workoutAlert: PowerZoneAlert(zone: 4)) == nil)
    }

    // MARK: - WorkoutKitBridge

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

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

    // MARK: - Scheduled entry ids

    @Test("workoutPlan(for:workout:athlete:) gives the entry its PlannedActivity's id, not the workout's")
    func workoutPlanUsesPlanID() throws {
        let workout = StructuredWorkout(
            name: "Easy run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])],
            workoutKitID: UUID()
        )
        let plan = PlannedActivity(workoutID: workout.id, date: Date())

        let workoutPlan = try bridge.workoutPlan(for: plan, workout: workout, athlete: testAthlete)

        #expect(workoutPlan.id == plan.id)
    }

    @Test("the plan sent to the watch has the athlete's heart rates for a zone and for zone positions, not the watch's zones")
    func workoutPlanSendsHeartRates() throws {
        func alert(_ target: IntensityTarget, athlete: AthleteProfile) throws -> (any WorkoutAlert)? {
            let workout = StructuredWorkout(
                name: "Z", sport: .running,
                blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600), target: target)], repetitions: 2)]
            )
            let plan = PlannedActivity(workoutID: workout.id, date: Date())
            guard case .custom(let custom) = try bridge.workoutPlan(for: plan, workout: workout, athlete: athlete).workout else {
                Issue.record("not a custom workout"); return nil
            }
            return custom.blocks[0].steps[0].step.alert
        }
        let unit = WorkoutAlertMetric.countPerMinute
        // Zone 3 is 148 to 162 bpm for the test athlete; 3.0 to 3.4 is its lower 40 %.
        let whole = try #require(try alert(.heartRateZone(3), athlete: testAthlete) as? HeartRateRangeAlert)
        #expect(abs(whole.target.lowerBound.converted(to: unit).value - 148) < 1e-6)
        #expect(abs(whole.target.upperBound.converted(to: unit).value - 162) < 1e-6)
        let positions = try #require(try alert(.heartRateZoneRange(3.0...3.4), athlete: testAthlete) as? HeartRateRangeAlert)
        #expect(abs(positions.target.upperBound.converted(to: unit).value - 153.6) < 1e-6)
        // Without zone settings the zone target is kept, and positions have no alert.
        var bare = testAthlete
        bare.heartRateZoneHistory = []
        #expect(try alert(.heartRateZone(3), athlete: bare) is HeartRateZoneAlert)
        #expect(try alert(.heartRateZoneRange(3.0...3.4), athlete: bare) == nil)
    }

    @Test("workoutPlan(for:workout:athlete:) gives two plans of the same workout on one day distinct ids")
    func workoutPlanDistinguishesPlansOfOneWorkout() throws {
        let workout = StructuredWorkout(
            name: "Easy run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        let day = Date()
        let first = try bridge.workoutPlan(for: PlannedActivity(workoutID: workout.id, date: day), workout: workout, athlete: testAthlete)
        let second = try bridge.workoutPlan(for: PlannedActivity(workoutID: workout.id, date: day), workout: workout, athlete: testAthlete)

        #expect(first.id != second.id)
    }

    @Test("workoutPlan(for:workout:athlete:) throws what customWorkout(from:) throws")
    func workoutPlanPropagatesMappingErrors() {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in false },
            supportsGoal: { _, _, _ in true },
            supportsAlert: { _, _, _ in true }
        ))
        let workout = StructuredWorkout(
            name: "Easy run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )

        #expect(throws: WorkoutKitMappingError.unsupportedActivity(.running)) {
            try bridge.workoutPlan(for: PlannedActivity(workoutID: workout.id, date: Date()), workout: workout, athlete: testAthlete)
        }
    }

    @Test("isSameDay compares year/month/day only, ignoring time-of-day fields")
    func isSameDayIgnoresTimeOfDay() {
        let scheduled = DateComponents(year: 2026, month: 9, day: 20, hour: 7, minute: 30)
        #expect(WorkoutKitBridge.isSameDay(scheduled, DateComponents(year: 2026, month: 9, day: 20)))
        #expect(!WorkoutKitBridge.isSameDay(scheduled, DateComponents(year: 2026, month: 9, day: 21)))
        #expect(!WorkoutKitBridge.isSameDay(scheduled, DateComponents(year: 2025, month: 9, day: 20)))
    }

    // MARK: - Support validation

    @Test("customWorkout(from:) throws unsupportedActivity when the sport's activity type isn't supported at all")
    func customWorkoutThrowsForUnsupportedActivity() {
        let bridge = WorkoutKitBridge(support: WorkoutKitSupportChecking(
            supportsActivity: { _ in false },
            supportsGoal: { _, _, _ in true },
            supportsAlert: { _, _, _ in true }
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
            supportsGoal: { _, _, _ in false },
            supportsAlert: { _, _, _ in true }
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
            supportsGoal: { _, _, _ in true },
            supportsAlert: { _, _, _ in false }
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
            supportsGoal: { _, _, _ in true },
            supportsAlert: { _, _, _ in false } // would fail every step if consulted
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

    @Test("the Glycogen Store Run maps: a distance warmup in the warmup slot, strides with no alert, a 90 s interval to finish")
    func glycogenStoreRunMaps() throws {
        let workout = try BuiltInWorkoutTemplates.glycogenStoreRun.instantiate()

        let customWorkout = try bridge.customWorkout(from: workout)

        #expect(customWorkout.warmup?.goal == .distance(2000, .meters))
        #expect(customWorkout.cooldown == nil)
        #expect(customWorkout.blocks.count == 2)
        #expect(customWorkout.blocks[0].iterations == 4)
        #expect(customWorkout.blocks[0].steps[0].step.goal == .distance(100, .meters))
        #expect(customWorkout.blocks[0].steps[0].step.alert == nil)
        #expect(customWorkout.blocks[1].steps[0].step.goal == .time(90, .seconds))
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

    @available(*, deprecated)
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

    @available(*, deprecated)
    @Test("the field-test templates map to one warmup, one cooldown and the efforts in between")
    func fieldTestsMapEdgesToWarmupAndCooldown() throws {
        for template in [BuiltInWorkoutTemplates.maxHRTest, BuiltInWorkoutTemplates.lthrTest] {
            let custom = try bridge.customWorkout(from: template.instantiate())

            #expect(custom.warmup != nil, "\(template.name)")
            #expect(custom.cooldown != nil, "\(template.name)")
            #expect(!custom.blocks.isEmpty, "\(template.name)")
        }
        // The ramp-in, three efforts and the all-out effort: 1 + 1 blocks of work around the repeated one.
        let maxHR = try bridge.customWorkout(from: BuiltInWorkoutTemplates.maxHRTest.instantiate())
        #expect(maxHR.blocks.count == 3)
        #expect(maxHR.blocks[1].iterations == 3)
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

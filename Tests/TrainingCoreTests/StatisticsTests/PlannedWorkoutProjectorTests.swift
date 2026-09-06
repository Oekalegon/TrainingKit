import Foundation
import Testing
@testable import TrainingCore

@Suite("PlannedWorkoutProjector")
struct PlannedWorkoutProjectorTests {
    private let projector = PlannedWorkoutProjector(durationEstimator: WorkoutDurationEstimator())

    private func workout(_ blocks: [WorkoutBlock]) -> StructuredWorkout {
        StructuredWorkout(name: "Test", sport: .running, blocks: blocks)
    }

    @Test("with no recorded heart-rate zone settings, falls back to nil distance and empty time-in-zone")
    func fallsBackWhenNoZoneSettingsRecorded() {
        let athlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )
        let steadyWorkout = workout([WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZone(2))])])

        let projection = projector.project(workout: steadyWorkout, athlete: athlete)

        #expect(projection.distanceMeters == nil)
        #expect(projection.duration == 600)
        #expect(projection.timeInZone == TimeInZone())
    }

    @Test("a block's repetitions multiply its steps' duration and distance")
    func repetitionsMultiplyDurationAndDistance() {
        let athlete = AthleteProfile.fixture()
        // Zone 2's midpoint ratio (0.65) resolves back to zone 2 via TimeInZoneBuilder.zone(for:),
        // so the target zone and the projected zone agree and the arithmetic stays checkable by
        // hand: secondsPerMeter(atZone: 2) = 240 * 1.20 / 1000 = 0.288.
        let repeatedWorkout = workout([
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZone(2))], repetitions: 3)
        ])

        let projection = projector.project(workout: repeatedWorkout, athlete: athlete)

        #expect(projection.duration == 1800)
        #expect(abs((projection.distanceMeters ?? 0) - 6250) < 0.01)
        #expect(projection.timeInZone.seconds[2] == 1800)
        #expect(projection.timeInZone.total == 1800)
    }

    @Test("when the athlete's zone method can't resolve every zone, projects at the default zone 3")
    func fallsBackToZoneThreeWhenBoundariesAreUnresolvable() {
        // `.lactateThreshold` with no recorded threshold heart rate makes every
        // `HeartRateZoneModel.zoneRatioRange(_:)` call return nil, so `TimeInZoneBuilder
        // .zoneBoundaries(_:)` returns nil and `project` falls back to zone 3 rather than crashing
        // or mis-assigning a zone.
        let athlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: [
                HeartRateZoneSettings(
                    effectiveDate: .distantPast,
                    restingHeartRateBPM: 50,
                    maxHeartRateBPM: 190,
                    lactateThresholdHeartRateBPM: nil,
                    zoneMethod: .lactateThreshold
                )
            ]
        )
        let openWorkout = workout([WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZone(2))])])

        let projection = projector.project(workout: openWorkout, athlete: athlete)

        #expect(projection.timeInZone.seconds[3] == 600)
        #expect(projection.timeInZone.seconds[2] == nil)
    }

    @Test("a step whose intensity resolves below zone 1 still projects distance at zone 1, not zone 0")
    func lowIntensityStepClampsToZoneOneForDistance() {
        let athlete = AthleteProfile.fixture()
        // `.rpe(2)` → intensityRatio 0.2, below the lowest Karvonen boundary (0.50) → zone 0. The
        // `max(zone, 1)` clamp in `project` means distance is computed at zone 1's pace multiplier
        // (1.35), not an arbitrary fallback for an unmapped zone 0.
        let easyWorkout = workout([WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600), target: .rpe(2))])])

        let projection = projector.project(workout: easyWorkout, athlete: athlete)

        let expectedDistance = 600 / athlete.paceModel.secondsPerMeter(atZone: 1)
        #expect(abs((projection.distanceMeters ?? 0) - expectedDistance) < 0.01)
        #expect(projection.timeInZone.seconds[0] == 600)
    }
}

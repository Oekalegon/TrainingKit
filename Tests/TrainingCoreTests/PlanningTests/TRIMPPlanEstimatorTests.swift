import Foundation
import Testing
@testable import TrainingCore

@Suite("TRIMPPlanEstimator")
struct TRIMPPlanEstimatorTests {
    let athlete = AthleteProfile(
        restingHeartRateBPM: 50,
        maxHeartRateBPM: 190,
        sex: .male,
        paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
        timeZone: TimeZone(identifier: "UTC")!
    )
    let estimator = TRIMPPlanEstimator()

    @Test("a workout with only .time steps at fixed zones is deterministic")
    func timeStepsAreDeterministic() {
        let workout = StructuredWorkout(
            name: "Steady run",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )

        let first = estimator.estimatedLoad(for: workout, athlete: athlete)
        let second = estimator.estimatedLoad(for: workout, athlete: athlete)

        #expect(first.value == second.value)
        #expect(first.value > 0)
        #expect(first.method == .estimatedFromPlan)
    }

    @Test(".distance steps respond to the athlete's pace model")
    func distanceStepsUsePaceModel() {
        let workout = StructuredWorkout(
            name: "5K",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(3))])]
        )

        var slowAthlete = athlete
        slowAthlete.paceModel = PaceModel(thresholdPaceSecondsPerKilometer: 400)

        let fastLoad = estimator.estimatedLoad(for: workout, athlete: athlete)
        let slowLoad = estimator.estimatedLoad(for: workout, athlete: slowAthlete)

        // A slower pace model means more time at the same intensity, so more load.
        #expect(slowLoad.value > fastLoad.value)
    }

    @Test("estimated load for a steady Z2 run is within a sane band of the equivalent measured TRIMP")
    func estimateApproximatesMeasuredLoad() throws {
        let zone2Midpoint = HeartRateZoneModel(athlete: athlete).zoneMidpointRatio(2)!
        let bpm = athlete.restingHeartRateBPM + zone2Midpoint * (athlete.maxHeartRateBPM - athlete.restingHeartRateBPM)

        let workout = StructuredWorkout(
            name: "60 min Z2",
            sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(2))])]
        )
        let estimatedLoad = estimator.estimatedLoad(for: workout, athlete: athlete)

        let samples = (0...60).map { HeartRateSample(time: Date(timeIntervalSince1970: Double($0) * 60), bpm: bpm) }
        let activity = Activity(source: .manual, sport: .running, start: Date(timeIntervalSince1970: 0), duration: 3600, heartRate: samples)
        let measuredLoad = try ExponentialTRIMPCalculator().load(for: activity, athlete: athlete)

        let ratio = estimatedLoad.value / measuredLoad.value
        #expect(ratio > 0.5 && ratio < 1.5)
    }
}

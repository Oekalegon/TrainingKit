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

}
#endif

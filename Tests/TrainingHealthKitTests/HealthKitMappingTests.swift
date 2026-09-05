#if canImport(HealthKit)
import HealthKit
import Foundation
import Testing
@testable import TrainingHealthKit
import TrainingCore

@Suite("HealthKit mapping")
struct HealthKitMappingTests {
    // MARK: - Sport

    @Test("common HealthKit activity types map to their direct Sport case")
    func sportDirectMappings() {
        #expect(Sport(healthKitActivityType: .running) == .running)
        #expect(Sport(healthKitActivityType: .cycling) == .cycling)
        #expect(Sport(healthKitActivityType: .swimming) == .swimming)
        #expect(Sport(healthKitActivityType: .traditionalStrengthTraining) == .strength)
        #expect(Sport(healthKitActivityType: .functionalStrengthTraining) == .strength)
        #expect(Sport(healthKitActivityType: .walking) == .walking)
        #expect(Sport(healthKitActivityType: .rowing) == .rowing)
    }

    @Test("an unmapped activity type falls back to .other, labeled with its raw value")
    func sportFallsBackToOther() {
        let sport = Sport(healthKitActivityType: .yoga)

        guard case .other(let label) = sport else {
            Issue.record("expected .other, got \(sport)")
            return
        }
        #expect(label.contains("\(HKWorkoutActivityType.yoga.rawValue)"))
    }

    // MARK: - BiologicalSex

    @Test("male and female map directly; notSet and other map to .unspecified")
    func biologicalSexMappings() {
        #expect(BiologicalSex(healthKitBiologicalSex: .male) == .male)
        #expect(BiologicalSex(healthKitBiologicalSex: .female) == .female)
        #expect(BiologicalSex(healthKitBiologicalSex: .notSet) == .unspecified)
        #expect(BiologicalSex(healthKitBiologicalSex: .other) == .unspecified)
    }

    // MARK: - HeartRateSample

    @Test("a heart-rate quantity sample maps to bpm at its start date")
    func heartRateSampleMapping() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1)
        let quantity = HKQuantity(unit: HeartRateSample.heartRateUnit, doubleValue: 142)
        let hkSample = HKQuantitySample(type: HKQuantityType(.heartRate), quantity: quantity, start: start, end: end)

        let sample = HeartRateSample(healthKitQuantitySample: hkSample)

        #expect(sample.time == start)
        #expect(abs(sample.bpm - 142) < 1e-9)
    }

    // MARK: - Activity

    @Test("a workout maps to an Activity keyed by its UUID, with distance and heart rate carried over")
    func activityMapping() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: nil
        )
        let heartRate = [HeartRateSample(time: start, bpm: 140)]

        let activity = Activity(healthKitWorkout: workout, heartRate: heartRate)

        #expect(activity.source == .healthKit(workout.uuid))
        #expect(activity.sport == .running)
        #expect(activity.start == start)
        #expect(activity.duration == 1800)
        #expect(activity.distanceMeters == 5000)
        #expect(activity.heartRate == heartRate)
        #expect(activity.perceivedExertion == nil)
    }

    @Test("a workout with no distance maps to a nil distanceMeters, not 0")
    func activityMappingNoDistance() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: start.addingTimeInterval(1800))

        let activity = Activity(healthKitWorkout: workout, heartRate: [])

        #expect(activity.distanceMeters == nil)
    }
}
#endif

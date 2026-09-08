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
        #expect(Sport(healthKitActivityType: .hiking) == .hiking)
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

    @Test("omitting existingID gives each mapped activity its own fresh id")
    func activityMappingWithoutExistingIDGetsFreshID() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800))

        let first = Activity(healthKitWorkout: workout, heartRate: [])
        let second = Activity(healthKitWorkout: workout, heartRate: [])

        // Same HealthKit workout mapped twice without a known existing id: same source (the
        // dedupe key), but two different fresh ids -- exactly why a caller upserting these by id
        // must look up and pass the existing one on a re-import, rather than relying on this
        // initializer alone to dedupe.
        #expect(first.source == second.source)
        #expect(first.id != second.id)
    }

    @Test("passing existingID reuses it, so a re-imported workout replaces rather than duplicates")
    func activityMappingWithExistingIDReusesIt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800))
        let existingID = UUID()

        let activity = Activity(healthKitWorkout: workout, heartRate: [], existingID: existingID)

        #expect(activity.id == existingID)
        #expect(activity.source == .healthKit(workout.uuid))
    }
}
#endif

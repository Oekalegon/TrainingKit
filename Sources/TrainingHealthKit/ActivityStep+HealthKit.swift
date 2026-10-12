import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension ActivityStep {
    /// The metadata key the Watch puts on a workout activity that is a step of a plan, with the step's
    /// position as `block.repetition.step` (e.g. `"2.3.1"`).
    static let keyPathMetadataKey = "WOIntervalStepKeyPath"
    /// The metadata key that says whether the Watch counted the step's goal as met.
    static let successfulMetadataKey = "WOIntervalStepSuccessful"

    /// Creates a step from one `HKWorkoutActivity` of a workout started from a plan (MVP2-146).
    ///
    /// Distance and heart rate come from the activity's own statistics, so distance is there only once
    /// the app may read it (see ``HealthKitAuthorization/readTypes``): a step without it still has its
    /// times and heart rate.
    ///
    /// - Parameter activity: A workout activity.
    /// - Returns: The step, or `nil` when `activity` isn't a step of a plan (no readable key path) or
    ///   hasn't ended.
    public init?(healthKitActivity activity: HKWorkoutActivity) {
        guard let keyPath = activity.metadata?[Self.keyPathMetadataKey] as? String,
              let components = Self.components(ofKeyPath: keyPath),
              let end = activity.endDate
        else { return nil }

        let heartRate = HKQuantityType(.heartRate)
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        self.init(
            block: components.block, repetition: components.repetition, step: components.step,
            start: activity.startDate, end: end, duration: activity.duration,
            distanceMeters: Self.distanceMeters(of: activity),
            averageHeartRateBPM: activity.statistics(for: heartRate)?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            elevationAscendedMeters: (activity.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
                .doubleValue(for: .meter()),
            wasGoalMet: (activity.metadata?[Self.successfulMetadataKey] as? NSNumber)?.boolValue
        )
    }

    /// The distance `activity` covered, whichever kind of distance its sport records (running,
    /// cycling, swimming...): the first statistic in a length unit.
    private static func distanceMeters(of activity: HKWorkoutActivity) -> Double? {
        for (type, statistics) in activity.allStatistics where type.is(compatibleWith: .meter()) {
            if let meters = statistics.sumQuantity()?.doubleValue(for: .meter()) { return meters }
        }
        return nil
    }
}
#endif

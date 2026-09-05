import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension Activity {
    /// Creates a completed activity from an `HKWorkout` and its heart-rate samples.
    ///
    /// Distance is mapped when the workout reports one; elevation, cadence, speed, and geographic
    /// bounds aren't — those need `HKWorkoutRoute`/`HKSeriesSample` parsing, out of scope for the
    /// HR-TRIMP import this adapter exists for. `perceivedExertion` is never set here; HealthKit
    /// doesn't report an RPE-equivalent, so it stays available for the user to enter by hand.
    ///
    /// - Parameters:
    ///   - workout: The HealthKit workout to import.
    ///   - heartRate: This workout's heart-rate samples, already scoped to its time range.
    public init(healthKitWorkout workout: HKWorkout, heartRate: [HeartRateSample]) {
        self.init(
            source: .healthKit(workout.uuid),
            sport: Sport(healthKitActivityType: workout.workoutActivityType),
            start: workout.startDate,
            duration: workout.duration,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            heartRate: heartRate
        )
    }
}
#endif

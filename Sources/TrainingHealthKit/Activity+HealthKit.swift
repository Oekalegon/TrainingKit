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
    ///   - existingID: The `id` of the `Activity` already stored for this workout's source, if
    ///     this is a re-import rather than the first import of it. `Activity.source` is the stable
    ///     dedupe key across re-imports, but `ActivityStore.upsert(_:)` matches by `id` — omitting
    ///     this (or passing `nil` when an existing activity's id could have been looked up) means a
    ///     re-import produces a *second* row for the same workout instead of updating the first.
    public init(healthKitWorkout workout: HKWorkout, heartRate: [HeartRateSample], existingID: UUID? = nil) {
        self.init(
            id: existingID ?? UUID(),
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

import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension Activity {
    /// Creates a completed activity from an `HKWorkout` and its heart-rate samples.
    ///
    /// Distance is mapped when the workout reports one, and speed when the caller passes it (MVP2-146);
    /// elevation, cadence and geographic bounds aren't — those need `HKWorkoutRoute`/`HKSeriesSample`
    /// parsing, out of scope for the HR-TRIMP import this adapter exists for. `perceivedExertion` is never set here; HealthKit
    /// doesn't report an RPE-equivalent, so it stays available for the user to enter by hand.
    ///
    /// - Parameters:
    ///   - workout: The HealthKit workout to import.
    ///   - heartRate: This workout's heart-rate samples, already scoped to its time range.
    ///   - speed: This workout's speed samples (MVP2-146), already scoped to its time range and
    ///     averaged into windows (see `HealthKitActivityImporter`); empty for a sport that records none.
    ///   - existingID: The `id` of the `Activity` already stored for this workout's source, if
    ///     this is a re-import rather than the first import of it. `Activity.source` is the stable
    ///     dedupe key across re-imports, but `ActivityStore.upsert(_:)` matches by `id`. Without
    ///     one the activity's `id` is the workout's own uuid, so every device that imports the
    ///     workout agrees on it and a synced plan's `completedActivityID` means the same activity
    ///     everywhere (MVP2-134), and a re-import updates the same row. Pass the stored id for an
    ///     activity imported before ids were derived this way (it has a random one); passing `nil`
    ///     there would make a *second* row for the workout.
    ///   - scheduledPlanID: The id of the `WorkoutPlan` the workout was started from, if any (see
    ///     `Activity.scheduledPlanID`); `HealthKitActivityImporter` reads it from WorkoutKit.
    ///
    /// The workout's own `workoutActivities` that are steps of a plan become ``Activity/steps`` (MVP2-146),
    /// in the order they were performed.
    public init(
        healthKitWorkout workout: HKWorkout,
        heartRate: [HeartRateSample],
        speed: [SpeedSample] = [],
        existingID: UUID? = nil,
        scheduledPlanID: UUID? = nil
    ) {
        self.init(
            id: existingID ?? workout.uuid,
            source: .healthKit(workout.uuid),
            sport: Sport(healthKitActivityType: workout.workoutActivityType),
            venue: Venue(healthKitWorkout: workout),
            start: workout.startDate,
            duration: workout.duration,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            heartRate: heartRate,
            speed: speed,
            scheduledPlanID: scheduledPlanID,
            steps: workout.workoutActivities.compactMap(ActivityStep.init(healthKitActivity:)).sorted { $0.start < $1.start }
        )
    }
}

extension Venue {
    /// The venue HealthKit records for `workout` in its `HKMetadataKeyIndoorWorkout` metadata, or
    /// `nil` when the workout doesn't say. HealthKit only knows indoors versus outdoors, so there's no
    /// surface.
    init?(healthKitWorkout workout: HKWorkout) {
        guard let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool else { return nil }
        self = indoor ? .indoor(nil) : .outdoor(nil)
    }
}
#endif

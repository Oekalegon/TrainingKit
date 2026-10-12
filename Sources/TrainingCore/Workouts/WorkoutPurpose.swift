/// What a ``StructuredWorkout`` is for, beyond the training it gives (MVP2-153).
///
/// Most workouts are ``general``: they're done for the training. A field test is done to measure the
/// athlete, and the result is read from the activity linked to its plan. The purpose is carried from
/// a ``WorkoutTemplate`` to the workouts it instantiates, and doesn't change the workout's estimated
/// or recorded load.
public enum WorkoutPurpose: String, Sendable, Codable, Hashable, CaseIterable {
    /// An ordinary workout, done for the training.
    case general
    /// A maximum-heart-rate field test: after a warm-up, three hard efforts with short recoveries and
    /// an all-out final effort. The result is the highest heart rate reached.
    case maxHRTest
    /// Friel's 30-minute lactate-threshold-heart-rate field test: after a warm-up, 30 minutes all-out.
    /// The result is the average heart rate over the last 20 minutes of the effort.
    case lthrTest
}

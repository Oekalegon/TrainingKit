/// Why a field test's result couldn't be measured from its activity (MVP2-154).
///
/// The athlete did the test, so a host app should say what was missing (for example "start the test
/// from the Watch workout") rather than ignore it.
public enum FieldTestError: Error, Sendable, Hashable {
    /// The activity has no usable heart rate: none recorded, or no value held long enough to count.
    case noHeartRate
    /// The test's effort couldn't be found in the activity: it wasn't started from the scheduled workout, or
    /// its length differs too much from the plan's for the effort to be located by time, or the plan has
    /// no timed effort.
    case effortNotLocated
    /// The recorded effort was much shorter than planned (less than 90% of it), so its last 20 minutes
    /// aren't the protocol's. The associated value is how long it was, in seconds.
    case effortTooShort(recordedSeconds: Double)
    /// Heart rate was recorded for too little of the 20 minutes to average (less than 80% covered).
    case insufficientHeartRate
    /// The measured value isn't above the resting heart rate on record, so it can't be right.
    case implausibleValue(bpm: Double)
}

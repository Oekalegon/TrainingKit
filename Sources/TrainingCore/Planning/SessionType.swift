/// The broad kind of a session, used to match what the athlete or a paradigm asks for to a
/// library workout.
///
/// Deliberately a small set of broad categories: the specifics of a workout (fartlek, fast finish,
/// the interval variants) belong to the template, not to a new case. ``RunType`` maps onto it
/// through ``RunType/sessionType``.
public enum SessionType: String, Sendable, Codable, Hashable, CaseIterable {
    /// A steady, comfortable aerobic run.
    case easy
    /// The longest run of the micro.
    case long
    /// Repeated hard efforts with recoveries.
    case interval
    /// A sustained effort at or around threshold pace.
    case tempo
    /// Repeated uphill efforts.
    case hillRepeats
    /// A very short, very easy run to aid recovery.
    case recovery
    /// A race.
    case race
}

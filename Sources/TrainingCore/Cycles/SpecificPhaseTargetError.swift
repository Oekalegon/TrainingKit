/// Why a ``SpecificPhaseTarget`` is not valid.
public enum SpecificPhaseTargetError: Error, Sendable, Hashable {
    /// The pace is not finite or not above zero.
    case invalidPace
    /// A heart-rate bound is not finite or not above zero.
    case invalidHeartRate
    /// The perceived effort is outside 1...10.
    case invalidPerceivedEffort
}

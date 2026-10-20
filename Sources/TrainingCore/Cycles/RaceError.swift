/// Why a ``Race`` is not valid.
public enum RaceError: Error, Sendable, Hashable {
    /// The distance is not finite or not above zero.
    case invalidDistance
}

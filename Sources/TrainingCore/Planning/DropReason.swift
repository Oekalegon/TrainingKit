/// Why ``DayAssigner`` could not place a requested session.
public enum DropReason: Sendable, Hashable {
    /// No day of the micro has a free run left that allows the session's run type.
    case noFreeDay
    /// There is a free day for a long run, but none has a free part where a long run is possible
    /// (``SlotOptions/longRunPossible``).
    case noLongRunSlot
    /// Every candidate day is closer to another hard session (or long run) than
    /// ``TrainingParadigm/minDaysBetweenHardSessions`` allows.
    case spacing
    /// The micro already has as many hard sessions as ``TrainingParadigm/maxHardSessionsPerMicro``
    /// allows for its length.
    case hardLimit
}

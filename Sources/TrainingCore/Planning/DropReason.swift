/// Why ``DayAssigner`` could not place a requested session.
public enum DropReason: Sendable, Codable, Hashable {
    /// No day of the micro has a free run left.
    case noFreeDay
    /// There are free runs, but no day allows the session's run type, because the athlete named it
    /// for other weekdays only (or, for a hard session, named every hard type elsewhere).
    case runTypeNotAllowed
    /// There is a free day for a long run, but none has a free part where a long run is possible
    /// (``SlotOptions/longRunPossible``).
    case noLongRunSlot
    /// Every candidate day is closer to another hard session (or long run) than
    /// ``TrainingParadigm/minDaysBetweenHardSessions`` allows, or (for a long run and an ultra target)
    /// placing it would exceed ``TrainingParadigm/maxBackToBackLongRunPairsPerMicro``.
    case spacing
    /// The micro already has as many hard sessions as ``TrainingParadigm/maxHardSessionsPerMicro``
    /// allows for its length.
    case hardLimit
}

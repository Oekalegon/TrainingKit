/// A session ``DayAssigner`` was asked to place but could not, with the reason.
public struct DroppedSession: Sendable, Hashable {
    /// What kind of session it was: ``RunType/long``, or the hard run type asked for.
    public let kind: Kind
    /// Why it could not be placed.
    public let reason: DropReason

    /// The kinds of session that can be requested and dropped.
    public enum Kind: Sendable, Hashable {
        /// A long run.
        case long
        /// A hard (threshold or interval) session.
        case hard
    }

    /// Creates a dropped session.
    ///
    /// - Parameters:
    ///   - kind: What kind of session it was.
    ///   - reason: Why it could not be placed.
    public init(kind: Kind, reason: DropReason) {
        self.kind = kind
        self.reason = reason
    }
}

/// The runs ``DayAssigner`` placed in a micro and the sessions it could not place.
public struct DayAssignmentResult: Sendable, Hashable {
    /// The placed runs, in date order and, within a day, in day-part order.
    public let assignments: [DayAssignment]
    /// The requested sessions that could not be placed; the generator reports each as a compromise.
    public let dropped: [DroppedSession]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - assignments: The placed runs.
    ///   - dropped: The requested sessions that could not be placed.
    public init(assignments: [DayAssignment], dropped: [DroppedSession]) {
        self.assignments = assignments
        self.dropped = dropped
    }
}

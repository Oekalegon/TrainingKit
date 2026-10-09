/// The recurring period a ``GoalTarget/volume(sport:measure:amount:per:)`` goal's amount is counted over.
///
/// A rolling period, not a date range: a goal has no dates (see ``Goal``).
public enum GoalPeriod: Sendable, Codable, Hashable, CaseIterable {
    /// Each week.
    case week
    /// Each month.
    case month
    /// Each year.
    case year
}

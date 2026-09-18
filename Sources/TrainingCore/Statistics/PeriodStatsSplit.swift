import Foundation

/// A calendar-day range's performed and planned totals, computed independently per sport by
/// ``StatisticsCalculator/periodStatsSplit(activities:plans:workouts:athlete:range:asOf:)`` — see
/// that method's own doc comment for why this is two independent figures rather than
/// ``PeriodStats``'s single merged one.
public struct PeriodStatsSplit: Sendable, Hashable {
    /// Totals from completed activities only, by sport.
    public let actual: [Sport: SportPeriodStats]
    /// Totals from planned activities only (dated `today` or later), by sport.
    public let planned: [Sport: SportPeriodStats]

    /// Creates a period stats split.
    ///
    /// - Parameters:
    ///   - actual: Totals from completed activities only, by sport.
    ///   - planned: Totals from planned activities only (dated `today` or later), by sport.
    public init(actual: [Sport: SportPeriodStats], planned: [Sport: SportPeriodStats]) {
        self.actual = actual
        self.planned = planned
    }
}

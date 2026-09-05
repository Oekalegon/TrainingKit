import Foundation

/// Descriptive totals over an arbitrary calendar-day range, computed by
/// ``StatisticsCalculator/periodStats(activities:plans:workouts:athlete:range:asOf:previous:)``.
///
/// ``WeeklyStats`` is the calendar-week special case of this same computation.
public struct PeriodStats: Sendable, Hashable {
    /// The calendar-day range these totals cover, in the athlete's timezone.
    public let range: ClosedRange<Date>
    /// `true` if any part of this period's totals came from planned activities rather than
    /// completed ones.
    public let isProjected: Bool
    /// Totals broken down by sport.
    public let bySport: [Sport: SportPeriodStats]
    /// Total distance covered across every sport.
    public let totalDistanceMeters: Double
    /// Total time across every sport.
    public let totalTime: TimeInterval
    /// Total training load across every sport.
    public let totalLoad: Double
    /// Seconds spent in each heart-rate zone across every activity in the period.
    public let timeInZone: TimeInZone
    /// How many activities (actual or, for a projected period, planned) contributed.
    public let activityCount: Int
    /// The longest single activity's duration in the period, or 0 if there were none.
    public let longestActivityTime: TimeInterval
    /// The longest single activity's distance in the period, or `nil` if none reported one.
    public let longestActivityDistanceMeters: Double?
    /// The change versus the previous period of the same length, or `nil` if none was supplied.
    public let delta: PeriodDelta?

    /// Creates a period statistic.
    public init(
        range: ClosedRange<Date>,
        isProjected: Bool,
        bySport: [Sport: SportPeriodStats],
        totalDistanceMeters: Double,
        totalTime: TimeInterval,
        totalLoad: Double,
        timeInZone: TimeInZone,
        activityCount: Int,
        longestActivityTime: TimeInterval,
        longestActivityDistanceMeters: Double?,
        delta: PeriodDelta?
    ) {
        self.range = range
        self.isProjected = isProjected
        self.bySport = bySport
        self.totalDistanceMeters = totalDistanceMeters
        self.totalTime = totalTime
        self.totalLoad = totalLoad
        self.timeInZone = timeInZone
        self.activityCount = activityCount
        self.longestActivityTime = longestActivityTime
        self.longestActivityDistanceMeters = longestActivityDistanceMeters
        self.delta = delta
    }
}

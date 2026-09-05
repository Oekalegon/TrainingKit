import Foundation

/// One sport's contribution to a ``PeriodStats``/``WeeklyStats`` total.
public struct SportPeriodStats: Sendable, Hashable {
    /// The sport these totals cover.
    public let sport: Sport
    /// Total distance covered in this sport during the period.
    public let distanceMeters: Double
    /// Total time spent in this sport during the period.
    public let time: TimeInterval
    /// Total training load from this sport during the period.
    public let load: Double
    /// Seconds spent in each heart-rate zone across this sport's activities.
    public let timeInZone: TimeInZone
    /// How many activities (actual or, for a projected period, planned) contributed.
    public let activityCount: Int

    /// Creates a per-sport period statistic.
    public init(
        sport: Sport,
        distanceMeters: Double,
        time: TimeInterval,
        load: Double,
        timeInZone: TimeInZone,
        activityCount: Int
    ) {
        self.sport = sport
        self.distanceMeters = distanceMeters
        self.time = time
        self.load = load
        self.timeInZone = timeInZone
        self.activityCount = activityCount
    }
}

/// A ``SportPeriodStats`` scoped to a calendar week; kept as a distinct name for readability at
/// ``WeeklyStats/bySport``, since the shape doesn't depend on period length.
public typealias SportWeekStats = SportPeriodStats

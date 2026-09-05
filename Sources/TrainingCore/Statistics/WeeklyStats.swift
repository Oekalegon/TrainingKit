import Foundation

/// Descriptive totals for one calendar week, the special case of ``PeriodStats`` that
/// ``StatisticsCalculator/weeklyStats(activities:plans:workouts:athlete:asOf:)`` returns for every
/// week touched by `activities`/`plans`, from the earliest through `today`.
///
/// Week boundaries come from ``AthleteProfile/weekStartsOn`` and ``AthleteProfile/timeZone``, the
/// same boundary rule ``DailyLoadSeries`` uses for daily bucketing.
public struct WeeklyStats: Identifiable, Sendable, Hashable {
    /// The week's start date, in the athlete's timezone.
    public var id: Date { weekStart }
    /// Start of the week, in the athlete's timezone.
    public let weekStart: Date
    /// `true` if any part of this week's totals came from planned activities rather than
    /// completed ones.
    public let isProjected: Bool
    /// Totals broken down by sport.
    public let bySport: [Sport: SportWeekStats]
    /// Total distance covered across every sport.
    public let totalDistanceMeters: Double
    /// Total time across every sport.
    public let totalTime: TimeInterval
    /// Total training load across every sport.
    public let totalLoad: Double
    /// Seconds spent in each heart-rate zone across every activity in the week.
    public let timeInZone: TimeInZone
    /// How many activities (actual or, for a projected week, planned) contributed.
    public let activityCount: Int
    /// The longest single activity's duration in the week, or 0 if there were none.
    public let longestActivityTime: TimeInterval
    /// The longest single activity's distance in the week, or `nil` if none reported one.
    public let longestActivityDistanceMeters: Double?
    /// The change versus the previous week, or `nil` for the first week in the series.
    public let delta: WeeklyDelta?

    /// Creates a weekly statistic.
    ///
    /// - Parameters:
    ///   - weekStart: Start of the week, in the athlete's timezone.
    ///   - isProjected: `true` if any part of this week's totals came from planned activities
    ///     rather than completed ones.
    ///   - bySport: Totals broken down by sport.
    ///   - totalDistanceMeters: Total distance covered across every sport.
    ///   - totalTime: Total time across every sport.
    ///   - totalLoad: Total training load across every sport.
    ///   - timeInZone: Seconds spent in each heart-rate zone across every activity in the week.
    ///   - activityCount: How many activities (actual or, for a projected week, planned)
    ///     contributed.
    ///   - longestActivityTime: The longest single activity's duration in the week, or 0 if there
    ///     were none.
    ///   - longestActivityDistanceMeters: The longest single activity's distance in the week, or
    ///     `nil` if none reported one.
    ///   - delta: The change versus the previous week, or `nil` for the first week in the series.
    public init(
        weekStart: Date,
        isProjected: Bool,
        bySport: [Sport: SportWeekStats],
        totalDistanceMeters: Double,
        totalTime: TimeInterval,
        totalLoad: Double,
        timeInZone: TimeInZone,
        activityCount: Int,
        longestActivityTime: TimeInterval,
        longestActivityDistanceMeters: Double?,
        delta: WeeklyDelta?
    ) {
        self.weekStart = weekStart
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

    /// Wraps the calendar-week special case of a ``PeriodStats`` computation.
    init(weekStart: Date, period: PeriodStats) {
        self.init(
            weekStart: weekStart,
            isProjected: period.isProjected,
            bySport: period.bySport,
            totalDistanceMeters: period.totalDistanceMeters,
            totalTime: period.totalTime,
            totalLoad: period.totalLoad,
            timeInZone: period.timeInZone,
            activityCount: period.activityCount,
            longestActivityTime: period.longestActivityTime,
            longestActivityDistanceMeters: period.longestActivityDistanceMeters,
            delta: period.delta
        )
    }
}

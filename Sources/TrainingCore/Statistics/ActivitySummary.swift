import Foundation

/// A descriptive summary of one completed ``Activity``, computed on demand by
/// ``StatisticsCalculator``.
///
/// Distinct from ``TrainingLoad``: this never feeds CTL/ATL, it's for display (activity lists,
/// per-activity detail) and for rolling up into ``WeeklyStats``/``PeriodStats``.
public struct ActivitySummary: Identifiable, Sendable, Hashable {
    /// The summarized activity's id.
    public var id: UUID { activityID }
    /// The summarized activity's id.
    public let activityID: UUID
    /// The summarized activity's sport.
    public let sport: Sport
    /// Total distance covered, if the activity reports one.
    public let distanceMeters: Double?
    /// How long the activity lasted.
    public let movingTime: TimeInterval
    /// Mean heart rate across ``Activity/heartRate``, or `nil` if empty.
    public let averageHeartRateBPM: Double?
    /// Seconds spent in each heart-rate zone.
    public let timeInZone: TimeInZone
    /// The activity's training load, from the first calculator that succeeds for it.
    public let load: TrainingLoad

    /// Creates an activity summary.
    public init(
        activityID: UUID,
        sport: Sport,
        distanceMeters: Double?,
        movingTime: TimeInterval,
        averageHeartRateBPM: Double?,
        timeInZone: TimeInZone,
        load: TrainingLoad
    ) {
        self.activityID = activityID
        self.sport = sport
        self.distanceMeters = distanceMeters
        self.movingTime = movingTime
        self.averageHeartRateBPM = averageHeartRateBPM
        self.timeInZone = timeInZone
        self.load = load
    }
}

import Foundation

/// The total training load for one calendar day, produced by ``DailyLoadSeries``.
public struct DayLoad: Sendable, Hashable {
    /// Start of the day, in the athlete's timezone.
    public let day: Date
    /// The total load for this day, in TRIMP units.
    public let load: Double
    /// `true` if any part of this day's load came from an estimate rather than a measured activity.
    public let isProjected: Bool

    /// Creates a day load.
    ///
    /// - Parameters:
    ///   - day: Start of the day, in the athlete's timezone.
    ///   - load: The total load for this day, in TRIMP units.
    ///   - isProjected: `true` if any part of this day's load came from an estimate.
    public init(day: Date, load: Double, isProjected: Bool) {
        self.day = day
        self.load = load
        self.isProjected = isProjected
    }
}

import Foundation

/// The thresholds that turn time-in-zone quantities into an ``IntensityCategory``.
///
/// Intensity is decided by how much time is spent at or above tempo effort, not by the mean
/// zone, the highest zone reached, or TRIMP: a long easy run accumulates a lot of TRIMP, one
/// short hard effort reaches zone 4 without making a run hard, and an interval session averages
/// out to a low zone because of its recoveries.
///
/// The defaults are starting points to be tuned against the athlete's own history.
public struct IntensityClassifierParameters: Sendable, Codable, Hashable {
    /// The least time in zones 4–5 that makes a session ``IntensityCategory/high``,
    /// regardless of how short the session is.
    public var highMinimumSeconds: TimeInterval
    /// The least share of the session in zones 4–5 that makes it ``IntensityCategory/high``.
    public var highMinimumFraction: Double
    /// The least time in zones 3–5 that makes a session ``IntensityCategory/medium``.
    public var mediumMinimumSeconds: TimeInterval
    /// The least share of the session in zones 3–5 that makes it ``IntensityCategory/medium``.
    public var mediumMinimumFraction: Double
    /// The least share of the session above zone 1 that makes it ``IntensityCategory/low``
    /// rather than ``IntensityCategory/veryLow``.
    public var lowMinimumFraction: Double

    /// Creates a parameter set; the defaults are the documented starting values.
    public init(
        highMinimumSeconds: TimeInterval = 6 * 60,
        highMinimumFraction: Double = 0.10,
        mediumMinimumSeconds: TimeInterval = 8 * 60,
        mediumMinimumFraction: Double = 0.15,
        lowMinimumFraction: Double = 0.10
    ) {
        self.highMinimumSeconds = highMinimumSeconds
        self.highMinimumFraction = highMinimumFraction
        self.mediumMinimumSeconds = mediumMinimumSeconds
        self.mediumMinimumFraction = mediumMinimumFraction
        self.lowMinimumFraction = lowMinimumFraction
    }

    /// Applies the intensity ladder.
    ///
    /// Each threshold is the larger of an absolute time and a share of the session, so a long
    /// session needs proportionally more quality time before it counts as harder.
    ///
    /// - Parameters:
    ///   - totalSeconds: The whole session's duration, including warm-up and cool-down.
    ///   - hardSeconds: Time in zones 4–5.
    ///   - moderateSeconds: Time in zone 3.
    ///   - aboveFirstZoneSeconds: Time in zones 2–5.
    public func category(
        totalSeconds: TimeInterval,
        hardSeconds: TimeInterval,
        moderateSeconds: TimeInterval,
        aboveFirstZoneSeconds: TimeInterval
    ) -> IntensityCategory {
        if hardSeconds >= max(highMinimumSeconds, highMinimumFraction * totalSeconds) {
            return .high
        }
        if hardSeconds + moderateSeconds >= max(mediumMinimumSeconds, mediumMinimumFraction * totalSeconds) {
            return .medium
        }
        if aboveFirstZoneSeconds >= lowMinimumFraction * totalSeconds {
            return .low
        }
        return .veryLow
    }
}

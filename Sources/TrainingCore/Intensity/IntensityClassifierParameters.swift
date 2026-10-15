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
    /// The shortest stretch in a zone band that counts when classifying recorded heart rate.
    /// Shorter excursions — an easy run touching zone 3 on a rise, a sensor spike — are ignored.
    /// Not used for planned workouts, whose steps are intentional however short.
    public var minimumExcursionSeconds: TimeInterval
    /// The time constant of the heart rate's lag behind effort, in seconds, that recorded heart
    /// rate is corrected for. Heart rate rises towards a new effort and falls back from it
    /// gradually, so a short hard rep peaks late (often in the recovery after it) and a recovery
    /// never fully settles before the next rep. 0 disables the correction.
    public var heartRateLagSeconds: TimeInterval

    /// Creates a parameter set; the defaults are the documented starting values.
    ///
    /// Values are made usable rather than trusted: times are clamped to be non-negative, fractions
    /// to `0...1`, and a value that isn't finite falls back to its default (a `NaN` threshold would
    /// otherwise make every comparison false and silently disable a category). Properties assigned
    /// after creation are not checked.
    public init(
        highMinimumSeconds: TimeInterval = 6 * 60,
        highMinimumFraction: Double = 0.10,
        mediumMinimumSeconds: TimeInterval = 8 * 60,
        mediumMinimumFraction: Double = 0.15,
        lowMinimumFraction: Double = 0.10,
        minimumExcursionSeconds: TimeInterval = 60,
        heartRateLagSeconds: TimeInterval = 30
    ) {
        self.highMinimumSeconds = Self.seconds(highMinimumSeconds, default: 6 * 60)
        self.highMinimumFraction = Self.fraction(highMinimumFraction, default: 0.10)
        self.mediumMinimumSeconds = Self.seconds(mediumMinimumSeconds, default: 8 * 60)
        self.mediumMinimumFraction = Self.fraction(mediumMinimumFraction, default: 0.15)
        self.lowMinimumFraction = Self.fraction(lowMinimumFraction, default: 0.10)
        self.minimumExcursionSeconds = Self.seconds(minimumExcursionSeconds, default: 60)
        self.heartRateLagSeconds = Self.seconds(heartRateLagSeconds, default: 30)
    }

    private static func seconds(_ value: TimeInterval, default fallback: TimeInterval) -> TimeInterval {
        value.isFinite ? max(value, 0) : fallback
    }

    private static func fraction(_ value: Double, default fallback: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : fallback
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

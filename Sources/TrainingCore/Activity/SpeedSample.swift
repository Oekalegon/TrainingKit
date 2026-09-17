import Foundation

/// A single speed reading at a point in time during an ``Activity``.
///
/// Kept as a raw stream (like ``HeartRateSample``), not just a summary, so a future pace-zone
/// time-in-zone statistic can be computed from it without re-importing the activity.
public struct SpeedSample: Sendable, Codable, Hashable {
    /// When this reading was taken.
    public let time: Date
    /// Speed in meters per second.
    public let metersPerSecond: Double

    /// Creates a speed sample.
    ///
    /// - Parameters:
    ///   - time: When this reading was taken.
    ///   - metersPerSecond: Speed in meters per second.
    public init(time: Date, metersPerSecond: Double) {
        self.time = time
        self.metersPerSecond = metersPerSecond
    }
}

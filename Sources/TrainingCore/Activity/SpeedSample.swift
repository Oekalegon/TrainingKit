import Foundation

/// A single speed reading at a point in time during an ``Activity``.
///
/// Kept as a raw stream (like ``HeartRateSample``), not just a summary, so a future pace-zone
/// time-in-zone statistic can be computed from it without re-importing the activity.
public struct SpeedSample: Sendable, Codable, Hashable {
    public let time: Date
    public let metersPerSecond: Double

    public init(time: Date, metersPerSecond: Double) {
        self.time = time
        self.metersPerSecond = metersPerSecond
    }
}

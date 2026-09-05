import Foundation

/// Time spent in each heart-rate zone during an activity or period, integrated from
/// ``Activity/heartRate`` using ``HeartRateSegmentIterator``'s trapezoid segments and gap rule.
///
/// Zone 0 means "below zone 1"; a sample pair straddling a zone boundary is split proportionally
/// between the two zones rather than assigned whole to one.
public struct TimeInZone: Sendable, Codable, Hashable {
    /// Seconds spent in each zone, keyed by zone number (0...5).
    public let seconds: [Int: TimeInterval]

    /// Creates a time-in-zone breakdown.
    public init(seconds: [Int: TimeInterval] = [:]) {
        self.seconds = seconds
    }

    /// The total time across all zones.
    public var total: TimeInterval {
        seconds.values.reduce(0, +)
    }

    /// The fraction of `total` spent in `zone`, or 0 if `total` is 0.
    public func fraction(of zone: Int) -> Double {
        guard total > 0 else { return 0 }
        return (seconds[zone] ?? 0) / total
    }

    /// Combines two breakdowns by summing seconds per zone, used to roll per-activity time in zone
    /// up into a week's or period's total.
    public static func + (lhs: TimeInZone, rhs: TimeInZone) -> TimeInZone {
        var combined = lhs.seconds
        for (zone, duration) in rhs.seconds {
            combined[zone, default: 0] += duration
        }
        return TimeInZone(seconds: combined)
    }
}

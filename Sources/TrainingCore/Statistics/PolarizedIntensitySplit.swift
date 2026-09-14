import Foundation

/// The 80/20 (polarized-training) split of time between low and moderate-to-high intensity,
/// derived from a ``TimeInZone`` breakdown.
///
/// Maps ``HeartRateZone``'s five zones onto the two-zone model behind the "80/20" guideline:
/// zone 0 ("below zone 1") and zones 1–2 (``HeartRateZone/recovery``, ``HeartRateZone/aerobic``)
/// count as low intensity — comfortable, conversational effort below the first
/// ventilatory/lactate threshold. Zones 3–5 (``HeartRateZone/tempo``, ``HeartRateZone/threshold``,
/// ``HeartRateZone/anaerobic``) count as moderate-to-high intensity — at or above it. Polarized
/// training guidance recommends roughly 80% low-intensity volume against 20% moderate-to-high for
/// endurance athletes, rather than the more even split many recreational athletes default to.
public struct PolarizedIntensitySplit: Sendable, Codable, Hashable {
    /// Seconds in zone 0 (below zone 1) plus zones 1–2.
    public let lowSeconds: TimeInterval
    /// Seconds in zones 3–5.
    public let moderateToHighSeconds: TimeInterval

    /// Creates a polarized split from its two seconds totals directly.
    ///
    /// - Parameters:
    ///   - lowSeconds: Seconds spent at low intensity (zone 0 and zones 1–2).
    ///   - moderateToHighSeconds: Seconds spent at moderate-to-high intensity (zones 3–5).
    public init(lowSeconds: TimeInterval, moderateToHighSeconds: TimeInterval) {
        self.lowSeconds = lowSeconds
        self.moderateToHighSeconds = moderateToHighSeconds
    }

    /// The total time across both buckets.
    public var total: TimeInterval {
        lowSeconds + moderateToHighSeconds
    }

    /// The fraction of `total` spent at low intensity, or 0 if `total` is 0.
    public var lowFraction: Double {
        guard total > 0 else { return 0 }
        return lowSeconds / total
    }

    /// The fraction of `total` spent at moderate-to-high intensity, or 0 if `total` is 0.
    public var moderateToHighFraction: Double {
        guard total > 0 else { return 0 }
        return moderateToHighSeconds / total
    }

    /// Combines two splits by summing each bucket, mirroring ``TimeInZone/+(_:_:)`` so a split can
    /// be rolled up the same way its source `TimeInZone` breakdowns are.
    public static func + (lhs: PolarizedIntensitySplit, rhs: PolarizedIntensitySplit) -> PolarizedIntensitySplit {
        PolarizedIntensitySplit(
            lowSeconds: lhs.lowSeconds + rhs.lowSeconds,
            moderateToHighSeconds: lhs.moderateToHighSeconds + rhs.moderateToHighSeconds
        )
    }
}

extension TimeInZone {
    /// This breakdown's time collapsed into ``PolarizedIntensitySplit``'s two-zone polarized model.
    public var polarizedSplit: PolarizedIntensitySplit {
        let low = (seconds[0] ?? 0) + (seconds[1] ?? 0) + (seconds[2] ?? 0)
        let moderateToHigh = (seconds[3] ?? 0) + (seconds[4] ?? 0) + (seconds[5] ?? 0)
        return PolarizedIntensitySplit(lowSeconds: low, moderateToHighSeconds: moderateToHigh)
    }
}

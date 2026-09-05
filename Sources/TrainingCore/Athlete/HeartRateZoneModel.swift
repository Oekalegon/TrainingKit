import Foundation

/// Derives heart-rate zone boundaries and Karvonen heart-rate-reserve ratios from a
/// ``HeartRateZoneSettings`` snapshot.
///
/// A snapshot, not an ``AthleteProfile`` directly, because these values change over the years —
/// callers pick the settings effective on the relevant date (``AthleteProfile/heartRateZoneSettings(asOf:)``
/// for a past activity, ``AthleteProfile/currentHeartRateZoneSettings`` for planning) before
/// building a model from them.
///
/// The "ratio" used throughout `TrainingCore` for the Banister TRIMP formula (in
/// ``ExponentialTRIMPCalculator`` and ``TRIMPPlanEstimator``) is always the Karvonen
/// heart-rate-reserve fraction, `(bpm - resting) / (max - resting)`, regardless of which
/// ``HeartRateZoneMethod`` is in effect — that's the ratio the formula is defined in terms of.
/// The zone method only changes which heart rates count as which zone.
public struct HeartRateZoneModel: Sendable {
    public let restingHeartRateBPM: Double
    public let maxHeartRateBPM: Double
    public let lactateThresholdHeartRateBPM: Double?
    public let method: HeartRateZoneMethod

    public init(
        restingHeartRateBPM: Double,
        maxHeartRateBPM: Double,
        lactateThresholdHeartRateBPM: Double? = nil,
        method: HeartRateZoneMethod = .karvonen
    ) {
        self.restingHeartRateBPM = restingHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.lactateThresholdHeartRateBPM = lactateThresholdHeartRateBPM
        self.method = method
    }

    public init(settings: HeartRateZoneSettings) {
        self.init(
            restingHeartRateBPM: settings.restingHeartRateBPM,
            maxHeartRateBPM: settings.maxHeartRateBPM,
            lactateThresholdHeartRateBPM: settings.lactateThresholdHeartRateBPM,
            method: settings.zoneMethod
        )
    }

    /// The Karvonen heart-rate-reserve ratio for a given heart rate.
    public func deltaHRRatio(for bpm: Double) -> Double {
        (bpm - restingHeartRateBPM) / (maxHeartRateBPM - restingHeartRateBPM)
    }

    /// The heart-rate-reserve ratio range for the given zone number (1...5), under this model's
    /// `method`. Returns `nil` for an out-of-range zone, or for `.lactateThreshold` when
    /// `lactateThresholdHeartRateBPM` hasn't been set.
    public func zoneRatioRange(_ zone: Int) -> ClosedRange<Double>? {
        switch method {
        case .karvonen:
            return Self.karvonenZoneRatioRanges[zone]
        case .percentageOfMaxHeartRate:
            guard let percentRange = Self.maxHeartRateZonePercentRanges[zone] else { return nil }
            return ratioRange(fromPercentRange: percentRange, ofReferenceBPM: maxHeartRateBPM)
        case .lactateThreshold:
            guard let lthr = lactateThresholdHeartRateBPM,
                  let percentRange = Self.lactateThresholdZonePercentRanges[zone]
            else { return nil }
            return ratioRange(fromPercentRange: percentRange, ofReferenceBPM: lthr)
        }
    }

    /// The midpoint ratio for the given zone number, used when a workout step targets a whole
    /// zone rather than an explicit range.
    public func zoneMidpointRatio(_ zone: Int) -> Double? {
        guard let range = zoneRatioRange(zone) else { return nil }
        return (range.lowerBound + range.upperBound) / 2
    }

    private func ratioRange(fromPercentRange percentRange: ClosedRange<Double>, ofReferenceBPM referenceBPM: Double) -> ClosedRange<Double> {
        let lowBPM = percentRange.lowerBound * referenceBPM
        let highBPM = percentRange.upperBound * referenceBPM
        return deltaHRRatio(for: lowBPM)...deltaHRRatio(for: highBPM)
    }

    /// Zones 1 (easiest) through 5 (hardest) as a fraction of heart-rate reserve.
    private static let karvonenZoneRatioRanges: [Int: ClosedRange<Double>] = [
        1: 0.50...0.60,
        2: 0.60...0.70,
        3: 0.70...0.80,
        4: 0.80...0.90,
        5: 0.90...1.00,
    ]

    /// Zones 1 through 5 as a fraction of maximum heart rate.
    private static let maxHeartRateZonePercentRanges: [Int: ClosedRange<Double>] = [
        1: 0.50...0.60,
        2: 0.60...0.70,
        3: 0.70...0.80,
        4: 0.80...0.90,
        5: 0.90...1.00,
    ]

    /// Zones 1 through 5 as a fraction of lactate threshold heart rate (Friel-style).
    private static let lactateThresholdZonePercentRanges: [Int: ClosedRange<Double>] = [
        1: 0.00...0.85,
        2: 0.85...0.89,
        3: 0.89...0.94,
        4: 0.94...0.99,
        5: 0.99...1.20,
    ]
}

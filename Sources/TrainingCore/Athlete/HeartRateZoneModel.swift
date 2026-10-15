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
    /// Resting heart rate, in beats per minute.
    public let restingHeartRateBPM: Double
    /// Maximum heart rate, in beats per minute.
    public let maxHeartRateBPM: Double
    /// Lactate threshold heart rate, in beats per minute, used when `method` is `.lactateThreshold`.
    public let lactateThresholdHeartRateBPM: Double?
    /// How zone boundaries are determined; see ``HeartRateZoneMethod``.
    public let method: HeartRateZoneMethod

    /// Creates a heart-rate zone model directly from raw values.
    ///
    /// - Parameters:
    ///   - restingHeartRateBPM: Resting heart rate, in beats per minute.
    ///   - maxHeartRateBPM: Maximum heart rate, in beats per minute.
    ///   - lactateThresholdHeartRateBPM: Lactate threshold heart rate, if known.
    ///   - method: How zone boundaries are determined; defaults to `.karvonen`.
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

    /// Creates a heart-rate zone model from a dated ``HeartRateZoneSettings`` snapshot.
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

    /// The heart-rate range, in bpm, for the given zone number (1...5) — the same boundaries
    /// ``zoneRatioRange(_:)`` reports, converted back from the Karvonen heart-rate-reserve ratio
    /// to bpm via this model's own resting/max heart rate (the inverse of ``deltaHRRatio(for:)``).
    /// This holds regardless of `method`: every method's boundaries are expressed as an HRR ratio
    /// internally (see this type's own doc comment), so converting back to bpm always uses the
    /// same resting/max pair. `nil` under the same conditions ``zoneRatioRange(_:)`` returns `nil`
    /// for (an out-of-range zone, or `.lactateThreshold` with no LTHR set).
    public func zoneBPMRange(_ zone: Int) -> ClosedRange<Double>? {
        guard let ratioRange = zoneRatioRange(zone) else { return nil }
        return bpm(forRatio: ratioRange.lowerBound)...bpm(forRatio: ratioRange.upperBound)
    }

    /// The heart rate, in bpm, for a given Karvonen heart-rate-reserve ratio — the inverse of
    /// ``deltaHRRatio(for:)``.
    private func bpm(forRatio ratio: Double) -> Double {
        ratio * (maxHeartRateBPM - restingHeartRateBPM) + restingHeartRateBPM
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
    ///
    /// These percentages are intentionally identical to ``karvonenZoneRatioRanges`` — that's not
    /// a copy-paste artifact. Both tables use the same commonly-quoted boundary percentages,
    /// applied to a different reference heart rate (max vs. heart-rate reserve); if the two are
    /// ever tuned independently based on updated sports-science guidance, update this comment.
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

    /// The heart-rate-reserve ratio a workout step's target intensity implies.
    ///
    /// Shared by ``TRIMPPlanEstimator`` (to weight planned TRIMP) and, through
    /// ``intensityZone(for:)``/``zone(for:)``, by `StatisticsCalculator`, ``WorkoutDurationEstimator``
    /// and the pace forecast (to bucket a planned step into a zone) so they can't
    /// silently drift apart on what a `.pace`/`.power`/`.rpe` target is assumed to mean.
    ///
    /// `.pace`/`.power` approximate a threshold-adjacent effort (roughly zone 4) since MVP 1 has no
    /// pace/power zone model; `.rpe(let rpe)` treats the Borg CR10 rating as a fraction of
    /// heart-rate reserve directly (`rpe / 10`). A `nil` target, or an out-of-range `.heartRateZone`,
    /// falls back to zone 3's midpoint.
    public func intensityRatio(for target: IntensityTarget?) -> Double {
        guard let target else {
            return zoneMidpointRatio(3) ?? 0.75
        }
        switch target {
        case .heartRateZone(let zone):
            return zoneMidpointRatio(zone) ?? zoneMidpointRatio(3) ?? 0.75
        case .heartRateRange(let low, let high):
            return (deltaHRRatio(for: low) + deltaHRRatio(for: high)) / 2
        case .pace, .power:
            return zoneMidpointRatio(4) ?? 0.85
        case .rpe(let rpe):
            return Double(rpe) / 10
        }
    }

    /// The zone (0...5) a workout step's target intensity falls in; 0 means below zone 1. This is
    /// the zone ``intensityRatio(for:)`` resolves to, so a `.pace`/`.power` target is zone 4 and a
    /// missing target zone 3 here as in the projector, the TRIMP estimator and the pace forecast.
    /// Falls back to ``fallbackZone(for:)`` when the method can't resolve every zone boundary.
    ///
    /// Use ``zone(for:)`` where the result picks a pace, which has no zone 0.
    public func intensityZone(for target: IntensityTarget?) -> Int {
        guard let boundaries = TimeInZoneBuilder.zoneBoundaries(self) else { return Self.fallbackZone(for: target) }
        return TimeInZoneBuilder.zone(for: intensityRatio(for: target), boundaries: boundaries)
    }

    /// ``intensityZone(for:)`` clamped to 1...5, for choosing a pace.
    public func zone(for target: IntensityTarget?) -> Int {
        max(intensityZone(for: target), 1)
    }

    /// The zone a target implies when there is no zone model to resolve it against: a
    /// `.heartRateZone` target's own zone (3 if out of range), zone 4 for `.pace`/`.power`
    /// (matching ``intensityRatio(for:)``), and zone 3 otherwise.
    public static func fallbackZone(for target: IntensityTarget?) -> Int {
        switch target {
        case .heartRateZone(let zone): return (1...5).contains(zone) ? zone : 3
        case .pace, .power: return 4
        default: return 3
        }
    }
}

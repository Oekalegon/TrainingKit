import Foundation

/// The heart-rate values and zone method effective from a given date, per ``AthleteProfile/heartRateZoneHistory``.
///
/// Resting/max heart rate and lactate threshold change over the years (fitness changes, watches
/// get recalibrated, a new threshold test is done), so recomputing an old activity's training
/// load needs the settings that were actually in effect on that activity's date, not today's.
public struct HeartRateZoneSettings: Sendable, Codable, Hashable {
    /// The date from which these settings apply, until superseded by a later entry.
    public var effectiveDate: Date
    /// Resting heart rate, in beats per minute.
    public var restingHeartRateBPM: Double
    /// Maximum heart rate, in beats per minute.
    public var maxHeartRateBPM: Double
    /// Where ``maxHeartRateBPM`` came from: an age formula or a workout.
    public var maxHeartRateSource: MaxHeartRateSource
    /// Used when `zoneMethod` is `.lactateThreshold`.
    public var lactateThresholdHeartRateBPM: Double?
    /// How zone boundaries are determined; see ``HeartRateZoneMethod``.
    public var zoneMethod: HeartRateZoneMethod

    /// Creates a heart-rate zone settings entry.
    ///
    /// - Parameters:
    ///   - effectiveDate: The date from which these settings apply.
    ///   - restingHeartRateBPM: Resting heart rate, in beats per minute.
    ///   - maxHeartRateBPM: Maximum heart rate, in beats per minute.
    ///   - maxHeartRateSource: Where `maxHeartRateBPM` came from; defaults to `.formula`.
    ///   - lactateThresholdHeartRateBPM: Lactate threshold heart rate, if known.
    ///   - zoneMethod: How zone boundaries are determined; defaults to `.karvonen`.
    public init(
        effectiveDate: Date,
        restingHeartRateBPM: Double,
        maxHeartRateBPM: Double,
        maxHeartRateSource: MaxHeartRateSource = .formula,
        lactateThresholdHeartRateBPM: Double? = nil,
        zoneMethod: HeartRateZoneMethod = .karvonen
    ) {
        self.effectiveDate = effectiveDate
        self.restingHeartRateBPM = restingHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.maxHeartRateSource = maxHeartRateSource
        self.lactateThresholdHeartRateBPM = lactateThresholdHeartRateBPM
        self.zoneMethod = zoneMethod
    }

    private enum CodingKeys: String, CodingKey {
        case effectiveDate, restingHeartRateBPM, maxHeartRateBPM, maxHeartRateSource
        case lactateThresholdHeartRateBPM, zoneMethod
    }

    /// Custom decoding so settings persisted before ``maxHeartRateSource`` existed still decode.
    /// Those values all came from the age formula, so the missing field defaults to `.formula`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        effectiveDate = try container.decode(Date.self, forKey: .effectiveDate)
        restingHeartRateBPM = try container.decode(Double.self, forKey: .restingHeartRateBPM)
        maxHeartRateBPM = try container.decode(Double.self, forKey: .maxHeartRateBPM)
        maxHeartRateSource = try container.decodeIfPresent(MaxHeartRateSource.self, forKey: .maxHeartRateSource)
            ?? .formula
        lactateThresholdHeartRateBPM = try container.decodeIfPresent(Double.self, forKey: .lactateThresholdHeartRateBPM)
        zoneMethod = try container.decode(HeartRateZoneMethod.self, forKey: .zoneMethod)
    }
}

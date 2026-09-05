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
    ///   - lactateThresholdHeartRateBPM: Lactate threshold heart rate, if known.
    ///   - zoneMethod: How zone boundaries are determined; defaults to `.karvonen`.
    public init(
        effectiveDate: Date,
        restingHeartRateBPM: Double,
        maxHeartRateBPM: Double,
        lactateThresholdHeartRateBPM: Double? = nil,
        zoneMethod: HeartRateZoneMethod = .karvonen
    ) {
        self.effectiveDate = effectiveDate
        self.restingHeartRateBPM = restingHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.lactateThresholdHeartRateBPM = lactateThresholdHeartRateBPM
        self.zoneMethod = zoneMethod
    }
}

import Foundation

/// The heart-rate values and zone method effective from a given date, per ``AthleteProfile/heartRateZoneHistory``.
///
/// Resting/max heart rate and lactate threshold change over the years (fitness changes, watches
/// get recalibrated, a new threshold test is done), so recomputing an old activity's training
/// load needs the settings that were actually in effect on that activity's date, not today's.
public struct HeartRateZoneSettings: Sendable, Codable, Hashable {
    /// The date from which these settings apply, until superseded by a later entry.
    public var effectiveDate: Date
    public var restingHeartRateBPM: Double
    public var maxHeartRateBPM: Double
    /// Used when `zoneMethod` is `.lactateThreshold`.
    public var lactateThresholdHeartRateBPM: Double?
    public var zoneMethod: HeartRateZoneMethod

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

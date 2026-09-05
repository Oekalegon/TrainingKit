/// How heart-rate zone boundaries are determined for an ``AthleteProfile``.
///
/// This only affects zone *classification* (which zone a given heart rate falls into, via
/// ``HeartRateZoneModel/zoneRatioRange(_:)``); the heart-rate-reserve ratio used by the Banister
/// TRIMP formula (``HeartRateZoneModel/deltaHRRatio(for:)``) is always Karvonen-based regardless
/// of this setting, since that's the ratio the formula is defined in terms of.
public enum HeartRateZoneMethod: Sendable, Codable, Hashable {
    /// Zones as a percentage of maximum heart rate. Needs only `maxHeartRateBPM`.
    case percentageOfMaxHeartRate
    /// Zones as a percentage of heart-rate reserve (Karvonen): `resting + percentage * (max - resting)`.
    /// Needs both `restingHeartRateBPM` and `maxHeartRateBPM`.
    case karvonen
    /// Zones as a percentage of lactate threshold heart rate. Needs `lactateThresholdHeartRateBPM`;
    /// falls back to no zone boundaries (see ``HeartRateZoneModel/zoneRatioRange(_:)``) if that's unset.
    case lactateThreshold
}

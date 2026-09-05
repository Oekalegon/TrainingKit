import Foundation

/// The athlete's physiological and calendar defaults, used throughout `TrainingCore` to turn raw
/// heart-rate data and workout plans into training load.
public struct AthleteProfile: Sendable, Codable {
    public var restingHeartRateBPM: Double
    public var maxHeartRateBPM: Double
    /// Optional lactate threshold heart rate, used when `heartRateZoneMethod` is `.lactateThreshold`.
    public var lactateThresholdHeartRateBPM: Double?
    /// How ``HeartRateZoneModel`` derives zone boundaries for this athlete.
    public var heartRateZoneMethod: HeartRateZoneMethod
    public var sex: BiologicalSex
    public var paceModel: PaceModel
    /// Boundary for daily bucketing in the fitness series (``DailyLoadSeries``).
    public var timeZone: TimeZone
    /// Boundary for weekly statistics; default is Monday.
    public var weekStartsOn: Weekday

    public init(
        restingHeartRateBPM: Double,
        maxHeartRateBPM: Double,
        lactateThresholdHeartRateBPM: Double? = nil,
        heartRateZoneMethod: HeartRateZoneMethod = .karvonen,
        sex: BiologicalSex,
        paceModel: PaceModel,
        timeZone: TimeZone,
        weekStartsOn: Weekday = .monday
    ) {
        self.restingHeartRateBPM = restingHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.lactateThresholdHeartRateBPM = lactateThresholdHeartRateBPM
        self.heartRateZoneMethod = heartRateZoneMethod
        self.sex = sex
        self.paceModel = paceModel
        self.timeZone = timeZone
        self.weekStartsOn = weekStartsOn
    }
}

import Foundation

/// The athlete's physiological and calendar defaults, used throughout `TrainingCore` to turn raw
/// heart-rate data and workout plans into training load.
public struct AthleteProfile: Sendable, Codable, Equatable {
    /// Used to select ``TRIMPCoefficients``.
    public var sex: BiologicalSex
    /// Turns a distance into a duration at a given heart-rate zone, for plan estimation.
    public var paceModel: PaceModel
    /// Boundary for daily bucketing in the fitness series (``DailyLoadSeries``).
    public var timeZone: TimeZone
    /// Boundary for weekly statistics; default is Monday.
    public var weekStartsOn: Weekday
    /// Every ``HeartRateZoneSettings`` this athlete has recorded, in any order. Recomputing an
    /// activity's load looks up the settings effective on that activity's date via
    /// ``heartRateZoneSettings(asOf:)`` rather than always using the latest entry, so that
    /// changing your resting/max heart rate or zone method today doesn't silently rewrite the
    /// history of past training load.
    public var heartRateZoneHistory: [HeartRateZoneSettings]

    /// Creates an athlete profile.
    ///
    /// - Parameters:
    ///   - sex: Used to select ``TRIMPCoefficients``.
    ///   - paceModel: Turns a distance into a duration at a given heart-rate zone.
    ///   - timeZone: Boundary for daily bucketing in the fitness series.
    ///   - weekStartsOn: Boundary for weekly statistics; defaults to Monday.
    ///   - heartRateZoneHistory: Every ``HeartRateZoneSettings`` this athlete has recorded.
    public init(
        sex: BiologicalSex,
        paceModel: PaceModel,
        timeZone: TimeZone,
        weekStartsOn: Weekday = .monday,
        heartRateZoneHistory: [HeartRateZoneSettings]
    ) {
        self.sex = sex
        self.paceModel = paceModel
        self.timeZone = timeZone
        self.weekStartsOn = weekStartsOn
        self.heartRateZoneHistory = heartRateZoneHistory
    }

    /// The most recently effective ``HeartRateZoneSettings``, used for planning (which is always
    /// about "who the athlete is now"). `nil` if no settings have been recorded yet.
    public var currentHeartRateZoneSettings: HeartRateZoneSettings? {
        heartRateZoneHistory.max { $0.effectiveDate < $1.effectiveDate }
    }

    /// The ``HeartRateZoneSettings`` in effect on the given date: the latest entry whose
    /// `effectiveDate` is on or before `date`.
    ///
    /// If `date` predates every recorded entry, the earliest known entry is returned instead of
    /// `nil` — an activity from before the athlete started tracking any heart-rate settings still
    /// needs *some* zones to be scored against, and the earliest known settings are a better
    /// approximation than refusing to score it at all. Returns `nil` only when no settings have
    /// been recorded at all.
    public func heartRateZoneSettings(asOf date: Date) -> HeartRateZoneSettings? {
        let sorted = heartRateZoneHistory.sorted { $0.effectiveDate < $1.effectiveDate }
        guard !sorted.isEmpty else { return nil }
        return sorted.last { $0.effectiveDate <= date } ?? sorted.first
    }
}

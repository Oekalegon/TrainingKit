import Foundation

/// The athlete's physiological and calendar defaults, used throughout `TrainingCore` to turn raw
/// heart-rate data and workout plans into training load.
public struct AthleteProfile: Sendable, Codable, Equatable {
    /// A stable identity for this athlete.
    ///
    /// Nothing in `TrainingCore` reads this itself — every store protocol, `TrainingModel`, and
    /// tool context already assumes "one instance = one athlete," and isolation between athletes
    /// comes from using separate store instances (e.g. separate `ModelContainer`s), not from
    /// filtering shared rows by this id. It exists for a host app to key a multi-athlete roster
    /// on — e.g. mapping `AthleteProfile.id` to which `TrainingModel`/container belongs to which
    /// athlete — without which there'd be nothing to distinguish one athlete's profile from
    /// another's once decoded.
    public let id: UUID
    /// A human-readable label, e.g. for a roster picker. Empty (not optional) when unset, so
    /// callers that don't need it never have to unwrap it.
    public var name: String
    /// Used to select ``TRIMPCoefficients``.
    public var sex: BiologicalSex
    /// Turns a distance into a duration at a given heart-rate zone, for plan estimation.
    public var paceModel: PaceModel
    /// Boundary for daily bucketing in the fitness series (``DailyLoadSeries``).
    public var timeZone: TimeZone
    /// Boundary for weekly statistics; default is Monday.
    public var weekStartsOn: Weekday
    /// The athlete's primary sport, e.g. for a weekly overview that highlights one sport's
    /// duration/distance/TRIMP change above the rest. Defaults to running.
    public var mainSport: Sport
    /// Every ``HeartRateZoneSettings`` this athlete has recorded, in any order. Recomputing an
    /// activity's load looks up the settings effective on that activity's date via
    /// ``heartRateZoneSettings(asOf:)`` rather than always using the latest entry, so that
    /// changing your resting/max heart rate or zone method today doesn't silently rewrite the
    /// history of past training load.
    public var heartRateZoneHistory: [HeartRateZoneSettings]
    /// The athlete's date of birth, if known (MVP2-124), e.g. read from HealthKit, for showing an
    /// age. `nil` until a source has provided one. Nothing in `TrainingCore` computes with it:
    /// ``TanakaHRMaxEstimator`` takes the date as an argument.
    public var dateOfBirth: Date?

    /// Creates an athlete profile.
    ///
    /// - Parameters:
    ///   - id: A stable identity for this athlete; defaults to a new random `UUID`.
    ///   - name: A human-readable label, e.g. for a roster picker; defaults to empty.
    ///   - sex: Used to select ``TRIMPCoefficients``.
    ///   - paceModel: Turns a distance into a duration at a given heart-rate zone.
    ///   - timeZone: Boundary for daily bucketing in the fitness series.
    ///   - weekStartsOn: Boundary for weekly statistics; defaults to Monday.
    ///   - mainSport: The athlete's primary sport; defaults to running.
    ///   - heartRateZoneHistory: Every ``HeartRateZoneSettings`` this athlete has recorded.
    ///   - dateOfBirth: The athlete's date of birth, if known; defaults to `nil`.
    public init(
        id: UUID = UUID(),
        name: String = "",
        sex: BiologicalSex,
        paceModel: PaceModel,
        timeZone: TimeZone,
        weekStartsOn: Weekday = .monday,
        mainSport: Sport = .running,
        heartRateZoneHistory: [HeartRateZoneSettings],
        dateOfBirth: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sex = sex
        self.paceModel = paceModel
        self.timeZone = timeZone
        self.weekStartsOn = weekStartsOn
        self.mainSport = mainSport
        self.heartRateZoneHistory = heartRateZoneHistory
        self.dateOfBirth = dateOfBirth
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sex, paceModel, timeZone, weekStartsOn, mainSport, heartRateZoneHistory, dateOfBirth
    }

    /// Custom decoding so profiles persisted before `mainSport` or `dateOfBirth` existed still
    /// decode, defaulting a missing `mainSport` to running and a missing `dateOfBirth` to `nil`
    /// rather than failing to load the athlete's whole profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sex = try container.decode(BiologicalSex.self, forKey: .sex)
        paceModel = try container.decode(PaceModel.self, forKey: .paceModel)
        timeZone = try container.decode(TimeZone.self, forKey: .timeZone)
        weekStartsOn = try container.decode(Weekday.self, forKey: .weekStartsOn)
        mainSport = try container.decodeIfPresent(Sport.self, forKey: .mainSport) ?? .running
        heartRateZoneHistory = try container.decode([HeartRateZoneSettings].self, forKey: .heartRateZoneHistory)
        dateOfBirth = try container.decodeIfPresent(Date.self, forKey: .dateOfBirth)
    }

    /// The athlete's age in whole years on `today`, or `nil` when ``dateOfBirth`` is unknown.
    ///
    /// Counted on calendar days in the athlete's ``timeZone``, so the age ticks over on the birthday
    /// itself, not hours before or after it, and never goes below zero for a birth date in the future.
    ///
    /// - Parameter today: The date to compute the age as of; injected rather than `Date()` for
    ///   determinism, matching the rest of `TrainingCore`.
    public func age(asOf today: Date) -> Int? {
        guard let dateOfBirth else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: dateOfBirth), to: calendar.startOfDay(for: today)).year ?? 0
        return max(years, 0)
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

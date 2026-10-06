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
    /// Every ``PaceSettings`` this athlete has recorded, in any order. Entered by the athlete, with
    /// the date each takes effect (MVP2-132); a profile stored before the history existed decodes
    /// its single pace model as one entry effective since the beginning of time.
    ///
    /// Keep it non-empty: the initializer, decoding and ``removingPaceSettings(on:)`` all do. Assigning
    /// an empty array leaves ``paceModel`` returning a placeholder 5:00 per kilometer rather than
    /// failing.
    public var paceHistory: [PaceSettings]
    /// Turns a distance into a duration at a given heart-rate zone, for plan estimation: the entry
    /// of ``paceHistory`` with the latest ``PaceSettings/effectiveDate``, since planning is always
    /// about who the athlete is now (the same rule as ``currentHeartRateZoneSettings``). Use
    /// ``paceModel(asOf:)`` for the model in effect on a given date.
    ///
    /// Setting it replaces that latest entry's model; to record a change with a date, use
    /// ``recordingPaceModel(_:from:)``.
    public var paceModel: PaceModel {
        get {
            paceHistory.max { $0.effectiveDate < $1.effectiveDate }?.paceModel
                ?? PaceModel(thresholdPaceSecondsPerKilometer: 300)
        }
        set {
            guard let index = paceHistory.indices.max(by: { paceHistory[$0].effectiveDate < paceHistory[$1].effectiveDate }) else {
                paceHistory = [PaceSettings(effectiveDate: .distantPast, paceModel: newValue)]
                return
            }
            paceHistory[index].paceModel = newValue
        }
    }
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
    ///
    /// HealthKit gives a calendar day, which arrives here as midnight in the device's time zone at
    /// the time of the read; ``age(asOf:)`` counts days in the athlete's ``timeZone``, so if the two
    /// zones differ the age can be a day off on the birthday itself.
    public var dateOfBirth: Date?
    /// Whether the resting heart rate in ``heartRateZoneHistory`` follows the one HealthKit reports
    /// (MVP2-132). On by default. While on, a host app merges HealthKit's resting heart rate into
    /// the history and doesn't offer to edit it; the athlete turns it off to enter their own. Nothing
    /// in `TrainingCore` reads it.
    public var usesHealthKitRestingHeartRate: Bool
    /// The athlete's picture, as encoded image data (MVP2-132), or `nil` for none. Chosen by the
    /// athlete, never read from another source. It's stored in the profile and so travels with it, so
    /// a host app should keep it small (a few tens of kilobytes). Nothing in `TrainingCore` reads it.
    public var avatarImageData: Data?

    /// Creates an athlete profile.
    ///
    /// - Parameters:
    ///   - id: A stable identity for this athlete; defaults to a new random `UUID`.
    ///   - name: A human-readable label, e.g. for a roster picker; defaults to empty.
    ///   - sex: Used to select ``TRIMPCoefficients``.
    ///   - paceModel: Turns a distance into a duration at a given heart-rate zone; recorded as one
    ///     ``PaceSettings`` entry effective since the beginning of time, unless `paceHistory` is given.
    ///   - timeZone: Boundary for daily bucketing in the fitness series.
    ///   - weekStartsOn: Boundary for weekly statistics; defaults to Monday.
    ///   - mainSport: The athlete's primary sport; defaults to running.
    ///   - heartRateZoneHistory: Every ``HeartRateZoneSettings`` this athlete has recorded.
    ///   - dateOfBirth: The athlete's date of birth, if known; defaults to `nil`.
    ///   - usesHealthKitRestingHeartRate: Whether the resting heart rate follows HealthKit; defaults
    ///     to `true`.
    ///   - avatarImageData: The athlete's picture as encoded image data, if they chose one; defaults
    ///     to `nil`.
    ///   - paceHistory: Every ``PaceSettings`` this athlete has recorded; when given and not empty, it
    ///     replaces the single entry `paceModel` would make.
    public init(
        id: UUID = UUID(),
        name: String = "",
        sex: BiologicalSex,
        paceModel: PaceModel,
        timeZone: TimeZone,
        weekStartsOn: Weekday = .monday,
        mainSport: Sport = .running,
        heartRateZoneHistory: [HeartRateZoneSettings],
        dateOfBirth: Date? = nil,
        usesHealthKitRestingHeartRate: Bool = true,
        avatarImageData: Data? = nil,
        paceHistory: [PaceSettings]? = nil
    ) {
        self.id = id
        self.name = name
        self.sex = sex
        // An empty history would leave `paceModel` with nothing to return, so it counts as none given.
        self.paceHistory = paceHistory.flatMap { $0.isEmpty ? nil : $0 }
            ?? [PaceSettings(effectiveDate: .distantPast, paceModel: paceModel)]
        self.timeZone = timeZone
        self.weekStartsOn = weekStartsOn
        self.mainSport = mainSport
        self.heartRateZoneHistory = heartRateZoneHistory
        self.dateOfBirth = dateOfBirth
        self.usesHealthKitRestingHeartRate = usesHealthKitRestingHeartRate
        self.avatarImageData = avatarImageData
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sex, paceModel, paceHistory, timeZone, weekStartsOn, mainSport, heartRateZoneHistory
        case dateOfBirth, usesHealthKitRestingHeartRate, avatarImageData
    }

    /// Custom decoding so profiles persisted before `mainSport`, `dateOfBirth`, `paceHistory`,
    /// `usesHealthKitRestingHeartRate` or `avatarImageData` existed still decode, defaulting a
    /// missing `mainSport` to running, a missing `dateOfBirth` or `avatarImageData` to `nil`, a
    /// missing `paceHistory` to the single `paceModel` entry and a missing
    /// `usesHealthKitRestingHeartRate` to `true`, rather than failing to load the athlete's whole
    /// profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sex = try container.decode(BiologicalSex.self, forKey: .sex)
        if let history = try container.decodeIfPresent([PaceSettings].self, forKey: .paceHistory), !history.isEmpty {
            paceHistory = history
        } else {
            let legacy = try container.decode(PaceModel.self, forKey: .paceModel)
            paceHistory = [PaceSettings(effectiveDate: .distantPast, paceModel: legacy)]
        }
        timeZone = try container.decode(TimeZone.self, forKey: .timeZone)
        weekStartsOn = try container.decode(Weekday.self, forKey: .weekStartsOn)
        mainSport = try container.decodeIfPresent(Sport.self, forKey: .mainSport) ?? .running
        heartRateZoneHistory = try container.decode([HeartRateZoneSettings].self, forKey: .heartRateZoneHistory)
        dateOfBirth = try container.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        usesHealthKitRestingHeartRate = try container.decodeIfPresent(Bool.self, forKey: .usesHealthKitRestingHeartRate) ?? true
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
    }

    /// Encodes the full ``paceHistory`` and also the current ``paceModel`` under its old key, so a
    /// reader from before the history existed still finds a pace model.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sex, forKey: .sex)
        try container.encode(paceModel, forKey: .paceModel)
        try container.encode(paceHistory, forKey: .paceHistory)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(weekStartsOn, forKey: .weekStartsOn)
        try container.encode(mainSport, forKey: .mainSport)
        try container.encode(heartRateZoneHistory, forKey: .heartRateZoneHistory)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(usesHealthKitRestingHeartRate, forKey: .usesHealthKitRestingHeartRate)
        try container.encodeIfPresent(avatarImageData, forKey: .avatarImageData)
    }

    /// The ``PaceModel`` in effect on `date`: the latest ``paceHistory`` entry whose effective date is
    /// on or before it, or the earliest entry when `date` predates them all, like
    /// ``heartRateZoneSettings(asOf:)``.
    ///
    /// - Parameter date: The date to look up.
    public func paceModel(asOf date: Date) -> PaceModel {
        let sorted = paceHistory.sorted { $0.effectiveDate < $1.effectiveDate }
        return (sorted.last { $0.effectiveDate <= date } ?? sorted.first)?.paceModel ?? paceModel
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

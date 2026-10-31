import Foundation

/// A training philosophy: the phases a plan moves through and the rules a plan in that style must
/// respect.
///
/// A paradigm names its phases (as ``CyclePhase`` values, in order), may replace individual
/// guardrail thresholds (``guardrailOverrides``), and sets the numbers behind the three paradigm
/// rules of ``PlanEvaluator``: ``PlanRule/intensityDistribution``, ``PlanRule/hardSessionSpacing``
/// and ``PlanRule/hardSessionsPerMicro``. Those rules run only when a paradigm is passed to
/// ``PlanEvaluator/evaluate(_:races:cycles:guardrails:sessions:paradigm:targetRace:)``. The built-in
/// paradigms (80/20 polarized, triphasic) are separate data (MVP5-103).
///
/// A session is *hard* when its ``PlanSession/intensity`` is at least ``hardIntensity``, or, when
/// ``hardSpeed`` is set, its ``PlanSession/speed`` is at least that. Setting ``hardSpeed`` lets a
/// paradigm place a maximal-speed but easy session (hill sprints) with the hard days, while
/// ``IntensityMix`` still counts its time as easy.
///
/// A plan aimed at an ultra race (``Race/isUltra``) uses ``resolved(for:)``: long runs are no
/// longer spaced like hard sessions, and ``maxLongRunMeters`` and
/// ``maxBackToBackLongRunPairsPerMicro`` apply (MVP5-138). A plan aimed at a 5k, 10k or half marathon
/// (``RaceDistanceClass``) uses the session profiles in ``distanceProfiles`` instead of ``sessionProfiles`` (MVP5-154).
///
/// Decoding is tolerant: every field but `name` is optional, and an unknown or missing key falls
/// back to the default.
public struct TrainingParadigm: Sendable, Codable, Hashable {
    /// The paradigm's display name, e.g. "80/20 polarized".
    public var name: String
    /// The phases the paradigm defines, in the order a plan moves through them.
    public var phases: [CyclePhase]
    /// Replacements for individual guardrail thresholds; see ``PlanGuardrails/Overrides``.
    public var guardrailOverrides: PlanGuardrails.Overrides
    /// The distribution target for phases with no entry in ``phaseMixes``; `nil` for none.
    public var defaultMix: IntensityMix?
    /// The distribution target per phase, taking precedence over ``defaultMix``.
    public var phaseMixes: [CyclePhase: IntensityMix]
    /// The lowest intensity category that makes a session hard; defaults to ``IntensityCategory/high``.
    public var hardIntensity: IntensityCategory
    /// The lowest speed level that makes a session hard; `nil` (the default) to ignore speed.
    public var hardSpeed: SpeedLevel?
    /// Whether ``PlanSession/isLongRun`` sessions count as hard for ``PlanRule/hardSessionSpacing``
    /// (but not for ``maxHardSessionsPerMicro``). A long run is usually spaced like a hard session;
    /// for an ultra target, where long runs of full length are not possible, ``resolved(for:)``
    /// sets this to `false`. Defaults to `false`.
    public var spacesLongRunsAsHard: Bool
    /// The longest a long run may be, in meters, for a plan with an ultra target; defaults to
    /// 35 km, `nil` for no ceiling. Full-length long runs are not possible for an ultra, so the
    /// generator stops short of the race distance. Only ``resolved(for:)`` with an ultra race keeps it.
    public var maxLongRunMeters: Double?
    /// The maximum number of back-to-back long-run pairs (long runs on two consecutive days) in a
    /// micro, by the micro's length in days (e.g. `[7: 1, 14: 2]`), for a plan with an ultra target.
    /// A micro whose length has no entry is not limited. The second run of a pair is not a hard
    /// session, and a pair does not count towards ``maxHardSessionsPerMicro``. Only
    /// ``resolved(for:)`` with an ultra race keeps it.
    public var maxBackToBackLongRunPairsPerMicro: [Int: Int]

    /// The phase a short lead time shortens, after any structural phase has been dropped (see
    /// ``LeadTimeCompromiser``): the race-specific phase, `.specific` for triphasic and `.peak` for
    /// the polarized paradigm. `nil` (the default) when the paradigm has none, so only the oldest
    /// phases are cut.
    public var shortenablePhase: CyclePhase?
    /// What each phase asks of its sessions (MVP5-118), for example one interval profile and a long
    /// run for a build phase; ``TemplateFitter`` matches each to a library template. A phase with no
    /// entry asks nothing. Empty for ``polarized8020``; ``triphasic`` carries the profiles its design
    /// document has decided (MVP5-147). For a marathon target and for no race; see ``distanceProfiles`` for the shorter races.
    public var sessionProfiles: [CyclePhase: [SessionProfile]]
    /// The session profiles for a plan aimed at a 5k, 10k or half marathon (MVP5-154): for a target race of one of
    /// these classes, ``resolved(for:)`` uses the class's profiles instead of ``sessionProfiles``, and there is no
    /// ``CalibrationWarning``. A class with no entry, and a marathon or ultra, use ``sessionProfiles``.
    public var distanceProfiles: [RaceDistanceClass: [CyclePhase: [SessionProfile]]]
    /// The race distance, in meters, the paradigm's percentages and zone mapping were calibrated for
    /// (42,195 for ``triphasic``); `nil` (the default) when it makes no claim. A plan aimed at a
    /// shorter race gets a ``CalibrationWarning`` (MVP5-143), unless ``distanceProfiles`` covers its class (MVP5-154):
    /// see ``calibrationWarning(for:)``.
    public var calibratedDistanceMeters: Double?
    /// The minimum number of days from one hard session to the next (Tuesday to Thursday is 2);
    /// `nil` switches ``PlanRule/hardSessionSpacing`` off.
    public var minDaysBetweenHardSessions: Int?
    /// The maximum number of hard sessions in a micro, by the micro's length in days
    /// (e.g. `[7: 2, 10: 3, 14: 4]`). A micro whose length has no entry is not checked.
    public var maxHardSessionsPerMicro: [Int: Int]

    /// Creates a paradigm.
    ///
    /// - Parameters:
    ///   - name: The display name.
    ///   - phases: The phases in order; defaults to none.
    ///   - guardrailOverrides: Guardrail replacements; defaults to none.
    ///   - defaultMix: The distribution target for phases without their own; defaults to none.
    ///   - phaseMixes: The distribution target per phase; defaults to none.
    ///   - hardIntensity: The lowest intensity category that makes a session hard; defaults to `.high`.
    ///   - hardSpeed: The lowest speed level that makes a session hard; defaults to `nil`.
    ///   - spacesLongRunsAsHard: Whether long runs are spaced like hard sessions; defaults to `false`.
    ///   - minDaysBetweenHardSessions: The minimum days between hard sessions; `nil` for no check.
    ///   - maxHardSessionsPerMicro: The maximum hard sessions per micro, by micro length in days.
    ///   - maxLongRunMeters: The longest a long run may be, in meters, for an ultra target; defaults to 35,000, `nil` for no ceiling.
    ///   - maxBackToBackLongRunPairsPerMicro: The maximum back-to-back long-run pairs per micro for
    ///     an ultra target, by micro length in days; defaults to no limit.
    ///   - shortenablePhase: The phase a short lead time shortens; defaults to `nil` (none).
    ///   - sessionProfiles: What each phase asks of its sessions; defaults to none.
    ///   - distanceProfiles: The profiles for a 5k, 10k or half marathon target; defaults to none.
    ///   - calibratedDistanceMeters: The race distance the numbers were calibrated for; defaults to
    ///     `nil` (none). A value that is not finite or not above zero becomes `nil`.
    public init(
        name: String,
        phases: [CyclePhase] = [],
        guardrailOverrides: PlanGuardrails.Overrides = PlanGuardrails.Overrides(),
        defaultMix: IntensityMix? = nil,
        phaseMixes: [CyclePhase: IntensityMix] = [:],
        hardIntensity: IntensityCategory = .high,
        hardSpeed: SpeedLevel? = nil,
        spacesLongRunsAsHard: Bool = false,
        minDaysBetweenHardSessions: Int? = nil,
        maxHardSessionsPerMicro: [Int: Int] = [:],
        maxLongRunMeters: Double? = 35_000,
        maxBackToBackLongRunPairsPerMicro: [Int: Int] = [:],
        shortenablePhase: CyclePhase? = nil,
        sessionProfiles: [CyclePhase: [SessionProfile]] = [:],
        distanceProfiles: [RaceDistanceClass: [CyclePhase: [SessionProfile]]] = [:],
        calibratedDistanceMeters: Double? = nil
    ) {
        self.name = name
        self.phases = phases
        self.guardrailOverrides = guardrailOverrides
        self.defaultMix = defaultMix
        self.phaseMixes = phaseMixes
        self.hardIntensity = hardIntensity
        self.hardSpeed = hardSpeed
        self.spacesLongRunsAsHard = spacesLongRunsAsHard
        self.minDaysBetweenHardSessions = minDaysBetweenHardSessions
        self.maxHardSessionsPerMicro = maxHardSessionsPerMicro
        self.maxLongRunMeters = Self.validPositive(maxLongRunMeters)
        self.maxBackToBackLongRunPairsPerMicro = Self.validPairLimits(maxBackToBackLongRunPairsPerMicro)
        self.shortenablePhase = shortenablePhase
        self.sessionProfiles = sessionProfiles
        self.distanceProfiles = distanceProfiles
        self.calibratedDistanceMeters = Self.validPositive(calibratedDistanceMeters)
    }

    /// A ceiling that is finite and above zero, otherwise `nil`.
    private static func validPositive(_ meters: Double?) -> Double? {
        meters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    /// The pair limits with negative values raised to zero.
    private static func validPairLimits(_ limits: [Int: Int]) -> [Int: Int] {
        limits.mapValues { max($0, 0) }
    }

    /// The paradigm as it applies to a plan aimed at `targetRace`.
    ///
    /// For an ultra (``Race/isUltra``) long runs are not spaced like hard sessions, so
    /// ``spacesLongRunsAsHard`` is `false`, and ``maxLongRunMeters`` and
    /// ``maxBackToBackLongRunPairsPerMicro`` stay. For any other race, or none, the two ultra
    /// settings are dropped and everything else is unchanged. For a race of a ``RaceDistanceClass`` that has
    /// ``distanceProfiles``, ``sessionProfiles`` is those profiles. ``DayAssigner``, ``PlanEvaluator`` and
    /// ``PlanGenerator`` call this with their `targetRace`.
    ///
    /// - Parameter targetRace: The race the plan builds towards, if any.
    public func resolved(for targetRace: Race?) -> TrainingParadigm {
        var result = self
        if targetRace?.isUltra == true {
            result.spacesLongRunsAsHard = false
        } else {
            result.maxLongRunMeters = nil
            result.maxBackToBackLongRunPairsPerMicro = [:]
        }
        if let profiles = distanceProfiles(for: targetRace) { result.sessionProfiles = profiles }
        return result
    }

    private func distanceProfiles(for targetRace: Race?) -> [CyclePhase: [SessionProfile]]? {
        targetRace.flatMap { RaceDistanceClass(distanceMeters: $0.distanceMeters) }.flatMap { distanceProfiles[$0] }
    }

    /// The warning for a plan aimed at `targetRace`, if the race is not the distance the paradigm is
    /// calibrated for (MVP5-143).
    ///
    /// `nil` when ``calibratedDistanceMeters`` is `nil`, when there is no race, when the race is an
    /// ultra (``Race/isUltra``; the paradigm's ultra settings cover it, ``resolved(for:)``), when the paradigm has
    /// ``distanceProfiles`` for the race's class (MVP5-154), or when its distance is within ``CalibrationWarning/tolerance`` of the calibration distance.
    ///
    /// - Parameter targetRace: The race the plan builds towards, if any.
    public func calibrationWarning(for targetRace: Race?) -> CalibrationWarning? {
        guard let calibrated = calibratedDistanceMeters, let race = targetRace, !race.isUltra,
              distanceProfiles(for: race) == nil else { return nil }
        let distance = race.distanceMeters
        guard distance.isFinite, abs(distance - calibrated) > calibrated * CalibrationWarning.tolerance else { return nil }
        return CalibrationWarning(raceDistanceMeters: distance, calibratedDistanceMeters: calibrated)
    }

    /// Whether `session` counts as hard under this paradigm.
    ///
    /// - Parameter session: The session to judge.
    public func isHard(_ session: PlanSession) -> Bool {
        if session.intensity >= hardIntensity { return true }
        if let hardSpeed, session.speed >= hardSpeed { return true }
        return false
    }

    /// Whether `session` counts as hard when spacing sessions: ``isHard(_:)``, or a long run when
    /// ``spacesLongRunsAsHard`` is set.
    ///
    /// - Parameter session: The session to judge.
    public func isHardForSpacing(_ session: PlanSession) -> Bool {
        isHard(session) || (spacesLongRunsAsHard && session.isLongRun)
    }

    private enum CodingKeys: String, CodingKey {
        case name, phases, guardrailOverrides, defaultMix, phaseMixes, hardIntensity, hardSpeed, spacesLongRunsAsHard
        case minDaysBetweenHardSessions, maxHardSessionsPerMicro, maxLongRunMeters, maxBackToBackLongRunPairsPerMicro, shortenablePhase, sessionProfiles, distanceProfiles, calibratedDistanceMeters
    }

    /// Decodes a paradigm; everything but `name` falls back to its default when absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        phases = try container.decodeIfPresent([CyclePhase].self, forKey: .phases) ?? []
        guardrailOverrides = try container.decodeIfPresent(PlanGuardrails.Overrides.self, forKey: .guardrailOverrides) ?? PlanGuardrails.Overrides()
        defaultMix = try container.decodeIfPresent(IntensityMix.self, forKey: .defaultMix)
        let mixes = try container.decodeIfPresent([String: IntensityMix].self, forKey: .phaseMixes) ?? [:]
        phaseMixes = Dictionary(mixes.map { (CyclePhase($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        hardIntensity = try container.decodeIfPresent(IntensityCategory.self, forKey: .hardIntensity) ?? .high
        hardSpeed = try container.decodeIfPresent(SpeedLevel.self, forKey: .hardSpeed)
        spacesLongRunsAsHard = try container.decodeIfPresent(Bool.self, forKey: .spacesLongRunsAsHard) ?? false
        minDaysBetweenHardSessions = try container.decodeIfPresent(Int.self, forKey: .minDaysBetweenHardSessions)
        let limits = try container.decodeIfPresent([String: Int].self, forKey: .maxHardSessionsPerMicro) ?? [:]
        maxHardSessionsPerMicro = Dictionary(limits.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { first, _ in first })
        if let stored = try container.decodeIfPresent(Double.self, forKey: .maxLongRunMeters) {
            maxLongRunMeters = Self.validPositive(stored)
        } else {
            maxLongRunMeters = 35_000
        }
        let pairs = try container.decodeIfPresent([String: Int].self, forKey: .maxBackToBackLongRunPairsPerMicro) ?? [:]
        maxBackToBackLongRunPairsPerMicro = Self.validPairLimits(Dictionary(pairs.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { first, _ in first }))
        shortenablePhase = try container.decodeIfPresent(CyclePhase.self, forKey: .shortenablePhase)
        let profiles = try container.decodeIfPresent([String: [LossyProfile]].self, forKey: .sessionProfiles) ?? [:]
        sessionProfiles = Dictionary(profiles.map { (CyclePhase($0.key), $0.value.compactMap(\.profile)) }, uniquingKeysWith: { first, _ in first })
        let classes = try container.decodeIfPresent([String: [String: [LossyProfile]]].self, forKey: .distanceProfiles) ?? [:]
        distanceProfiles = Dictionary(classes.compactMap { key, phases in
            RaceDistanceClass(rawValue: key).map { ($0, Dictionary(phases.map { (CyclePhase($0.key), $0.value.compactMap(\.profile)) }, uniquingKeysWith: { first, _ in first })) }
        }, uniquingKeysWith: { first, _ in first })
        calibratedDistanceMeters = Self.validPositive(try container.decodeIfPresent(Double.self, forKey: .calibratedDistanceMeters))
    }

    /// A profile that reads as `nil` when it cannot be decoded (an unknown session type), so one bad entry does not fail the paradigm.
    private struct LossyProfile: Decodable {
        let profile: SessionProfile?

        init(from decoder: Decoder) throws {
            profile = try? SessionProfile(from: decoder)
        }
    }

    /// Encodes the paradigm; dictionary keys are written as strings (phase ids, micro lengths).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(phases, forKey: .phases)
        try container.encode(guardrailOverrides, forKey: .guardrailOverrides)
        try container.encodeIfPresent(defaultMix, forKey: .defaultMix)
        try container.encode(Dictionary(uniqueKeysWithValues: phaseMixes.map { ($0.key.id, $0.value) }), forKey: .phaseMixes)
        try container.encode(hardIntensity, forKey: .hardIntensity)
        try container.encodeIfPresent(hardSpeed, forKey: .hardSpeed)
        try container.encode(spacesLongRunsAsHard, forKey: .spacesLongRunsAsHard)
        try container.encodeIfPresent(minDaysBetweenHardSessions, forKey: .minDaysBetweenHardSessions)
        try container.encode(Dictionary(uniqueKeysWithValues: maxHardSessionsPerMicro.map { (String($0.key), $0.value) }), forKey: .maxHardSessionsPerMicro)
        try container.encodeIfPresent(maxLongRunMeters, forKey: .maxLongRunMeters)
        try container.encode(Dictionary(uniqueKeysWithValues: maxBackToBackLongRunPairsPerMicro.map { (String($0.key), $0.value) }), forKey: .maxBackToBackLongRunPairsPerMicro)
        try container.encodeIfPresent(shortenablePhase, forKey: .shortenablePhase)
        try container.encode(Dictionary(uniqueKeysWithValues: sessionProfiles.map { ($0.key.id, $0.value) }), forKey: .sessionProfiles)
        try container.encode(
            Dictionary(uniqueKeysWithValues: distanceProfiles.map { ($0.key.rawValue, Dictionary(uniqueKeysWithValues: $0.value.map { ($0.key.id, $0.value) })) }),
            forKey: .distanceProfiles
        )
        try container.encodeIfPresent(calibratedDistanceMeters, forKey: .calibratedDistanceMeters)
    }
}

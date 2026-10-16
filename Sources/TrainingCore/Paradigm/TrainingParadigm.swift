import Foundation

/// A training philosophy: the phases a plan moves through and the rules a plan in that style must
/// respect.
///
/// A paradigm names its phases (as ``CyclePhase`` values, in order), may replace individual
/// guardrail thresholds (``guardrailOverrides``), and sets the numbers behind the three paradigm
/// rules of ``PlanEvaluator``: ``PlanRule/intensityDistribution``, ``PlanRule/hardSessionSpacing``
/// and ``PlanRule/hardSessionsPerMicro``. Those rules run only when a paradigm is passed to
/// ``PlanEvaluator/evaluate(_:races:cycles:guardrails:sessions:paradigm:)``. The built-in
/// paradigms (80/20 polarized, triphasic) are separate data (MVP5-103).
///
/// A session is *hard* when its ``PlanSession/intensity`` is at least ``hardIntensity``, or, when
/// ``hardSpeed`` is set, its ``PlanSession/speed`` is at least that. Setting ``hardSpeed`` lets a
/// paradigm place a maximal-speed but easy session (hill sprints) with the hard days, while
/// ``IntensityMix`` still counts its time as easy.
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
    ///   - minDaysBetweenHardSessions: The minimum days between hard sessions; `nil` for no check.
    ///   - maxHardSessionsPerMicro: The maximum hard sessions per micro, by micro length in days.
    public init(
        name: String,
        phases: [CyclePhase] = [],
        guardrailOverrides: PlanGuardrails.Overrides = PlanGuardrails.Overrides(),
        defaultMix: IntensityMix? = nil,
        phaseMixes: [CyclePhase: IntensityMix] = [:],
        hardIntensity: IntensityCategory = .high,
        hardSpeed: SpeedLevel? = nil,
        minDaysBetweenHardSessions: Int? = nil,
        maxHardSessionsPerMicro: [Int: Int] = [:]
    ) {
        self.name = name
        self.phases = phases
        self.guardrailOverrides = guardrailOverrides
        self.defaultMix = defaultMix
        self.phaseMixes = phaseMixes
        self.hardIntensity = hardIntensity
        self.hardSpeed = hardSpeed
        self.minDaysBetweenHardSessions = minDaysBetweenHardSessions
        self.maxHardSessionsPerMicro = maxHardSessionsPerMicro
    }

    /// Whether `session` counts as hard under this paradigm.
    ///
    /// - Parameter session: The session to judge.
    public func isHard(_ session: PlanSession) -> Bool {
        if session.intensity >= hardIntensity { return true }
        if let hardSpeed, session.speed >= hardSpeed { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case name, phases, guardrailOverrides, defaultMix, phaseMixes, hardIntensity, hardSpeed
        case minDaysBetweenHardSessions, maxHardSessionsPerMicro
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
        minDaysBetweenHardSessions = try container.decodeIfPresent(Int.self, forKey: .minDaysBetweenHardSessions)
        let limits = try container.decodeIfPresent([String: Int].self, forKey: .maxHardSessionsPerMicro) ?? [:]
        maxHardSessionsPerMicro = Dictionary(limits.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { first, _ in first })
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
        try container.encodeIfPresent(minDaysBetweenHardSessions, forKey: .minDaysBetweenHardSessions)
        try container.encode(Dictionary(uniqueKeysWithValues: maxHardSessionsPerMicro.map { (String($0.key), $0.value) }), forKey: .maxHardSessionsPerMicro)
    }
}

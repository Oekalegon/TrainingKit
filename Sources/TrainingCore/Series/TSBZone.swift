/// A qualitative classification of Training Stress Balance (``FitnessMetrics/tsb``, CTL − ATL)
/// into named training-state bands — the standard coaching interpretation of TSB (see Joe Friel's
/// *Training Bible* and TrainingPeaks' own Performance Management Chart guidance) for reading
/// freshness/fatigue at a glance rather than as a raw number.
///
/// Boundaries run on `tsb` itself, ascending from most negative (``injuryRisk``, heavy
/// accumulated fatigue) to most positive (``detraining``, fitness now fading from sustained
/// rest). ``race``'s own boundaries are deliberately *not* independent literals: they're the same
/// ``PlanGuardrails/minTSBOnRaceDay``/``PlanGuardrails/maxTSBOnRaceDay`` the plan evaluator itself
/// checks race-day TSB against (``PlanEvaluator``), so this classification and "is this athlete
/// race-ready" can't silently disagree — including after those guardrails are tuned per-athlete
/// (the design doc anticipates this happening from observed outcomes).
public enum TSBZone: Sendable, Codable, Hashable, CaseIterable {
    /// `tsb < -30`: fatigue is badly outpacing fitness — the classic overreaching zone, with
    /// elevated injury/illness risk if sustained.
    case injuryRisk
    /// `-30 ..< -10`: sustained hard training, building fitness at a normal, tolerable cost.
    case training
    /// `-10 ..< minTSBOnRaceDay`: roughly balanced — fatigue has largely cleared without
    /// meaningful fitness loss, a sustainable zone for maintaining.
    case recovery
    /// `minTSBOnRaceDay ..< maxTSBOnRaceDay`: fresh with fitness still largely intact — the same
    /// taper/race-ready window ``PlanEvaluator`` checks race-day TSB against.
    case race
    /// `tsb >= maxTSBOnRaceDay`: rest sustained long enough to start losing fitness, not just
    /// fatigue.
    case detraining

    /// The lower bound (inclusive) of each zone, in ascending `tsb` order — the single source of
    /// truth ``init(tsb:guardrails:)`` switches on, so the boundaries can't drift out of sync with
    /// each other. `race`/`detraining`'s bounds come from `guardrails` rather than being repeated
    /// as separate literals — see this type's own doc comment for why.
    private static func lowerBounds(guardrails: PlanGuardrails) -> [(zone: TSBZone, lowerBound: Double)] {
        [
            (.injuryRisk, -.infinity),
            (.training, -30),
            (.recovery, -10),
            (.race, guardrails.minTSBOnRaceDay),
            (.detraining, guardrails.maxTSBOnRaceDay),
        ]
    }

    /// Classifies `tsb` into its zone.
    ///
    /// A `tsb` of `.nan` (not reachable today — unlike ``FitnessMetrics/monotony``/`.strain`,
    /// `tsb` is always a subtraction of two finite EWMA values — but guarded against regardless)
    /// falls back to ``injuryRisk``, since every `>=` comparison against it is `false`: treat that
    /// as "couldn't classify, assume the alarming case" rather than a meaningful reading.
    ///
    /// - Parameters:
    ///   - tsb: The training stress balance value to classify.
    ///   - guardrails: Where ``race``'s boundaries come from; defaults to
    ///     `PlanGuardrails()`. Pass the athlete's own (possibly tuned) guardrails so this stays
    ///     consistent with what ``PlanEvaluator`` considers race-ready for them.
    public init(tsb: Double, guardrails: PlanGuardrails = PlanGuardrails()) {
        self = Self.lowerBounds(guardrails: guardrails).last { tsb >= $0.lowerBound }?.zone ?? .injuryRisk
    }
}

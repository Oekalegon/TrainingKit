/// Which guardrail a ``PlanFinding`` came from.
///
/// The first four run on `[FitnessMetrics]` alone; the last needs the `cycles` parameter of
/// ``PlanEvaluator/evaluate(_:races:cycles:guardrails:)`` and is skipped without it.
public enum PlanRule: Sendable, Codable, Hashable {
    /// A day's monotony against ``PlanGuardrails/maxMonotony``.
    case monotony
    /// A day's strain percentile within the athlete's own trailing distribution, against
    /// ``PlanGuardrails/maxStrainPercentile``.
    case strain
    /// TSB on a ``Race/date`` against ``PlanGuardrails/minTSBOnRaceDay``/``PlanGuardrails/maxTSBOnRaceDay``.
    case raceDayTSB
    /// Any day's TSB against ``PlanGuardrails/minAcceptableTSB``/``PlanGuardrails/maxAcceptableTSB``
    /// — unlike ``raceDayTSB``, checked every day, not just race days: the direct freshness/fatigue
    /// signal (TSB = CTL − ATL), independent of whether the plan has any known phase (build,
    /// recovery, taper) to judge it against.
    case tsbBand
    /// A build-phase micro's load relative to the previous build-phase micro, against
    /// ``PlanGuardrails/maxBuildProgressionFraction``.
    case buildProgression
}

/// Which guardrail a ``PlanFinding`` came from.
///
/// The first four run on `[FitnessMetrics]` alone; ``longestRun`` reads the `sessions`
/// parameter of ``PlanEvaluator/evaluate(_:races:cycles:guardrails:sessions:paradigm:)`` and finds
/// nothing without them. The last three are the paradigm rules: they run only when a
/// ``TrainingParadigm`` is supplied, and the two that read micros also need `cycles`.
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
    /// A run longer than the longest run of the previous 28 days by more than
    /// ``PlanGuardrails/maxLongestRunIncreaseFraction``. A ``Severity/risk``.
    case longestRun
    /// A micro's share of planned time per intensity category or speed level against the target of
    /// its phase in ``TrainingParadigm/phaseMixes``/``TrainingParadigm/defaultMix`` (``IntensityMix``).
    /// A ``Severity/warning``.
    case intensityDistribution
    /// Two hard sessions (and long runs, when ``TrainingParadigm/spacesLongRunsAsHard`` is set)
    /// closer than ``TrainingParadigm/minDaysBetweenHardSessions``.
    /// A ``Severity/risk``.
    case hardSessionSpacing
    /// More hard sessions in a micro than ``TrainingParadigm/maxHardSessionsPerMicro`` allows for
    /// its length. A ``Severity/risk``.
    case hardSessionsPerMicro
}

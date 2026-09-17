/// Which guardrail a ``PlanFinding`` came from.
///
/// The first five run on `[FitnessMetrics]` alone; the rest need the `cycles` parameter of
/// ``PlanEvaluator/evaluate(_:races:cycles:guardrails:)`` and are skipped without it.
public enum PlanRule: Sendable, Codable, Hashable {
    /// CTL[d] − CTL[d−7] against ``PlanGuardrails/maxCTLRampPerWeek``.
    case ctlRamp
    /// ATL[d] / CTL[d] against ``PlanGuardrails/maxATLtoCTLRatio``/``PlanGuardrails/minATLtoCTLRatio``.
    case atlToCTLRatio
    /// A day's monotony against ``PlanGuardrails/maxMonotony``.
    case monotony
    /// A day's strain percentile within the athlete's own trailing distribution, against
    /// ``PlanGuardrails/maxStrainPercentile``.
    case strain
    /// TSB on a ``Race/date`` against ``PlanGuardrails/minTSBOnRaceDay``/``PlanGuardrails/maxTSBOnRaceDay``.
    case raceDayTSB
    /// A recovery-phase micro's load relative to the micro before it, against
    /// ``PlanGuardrails/recoveryLoadFraction``.
    case recoveryMicro
    /// A build-phase micro's load relative to the previous build-phase micro, against
    /// ``PlanGuardrails/maxBuildProgressionFraction``.
    case buildProgression
    /// CTL gain across a base/build meso, against ``PlanGuardrails/minCTLGainPerMeso``.
    case mesoProgress
    /// CTL drop and TSB trend across a taper meso, against ``PlanGuardrails/maxTaperCTLDropFraction``.
    case taperShape
    /// Consecutive non-recovery micros, against ``PlanGuardrails/maxMicrosWithoutRecovery``.
    case consecutiveLoad
}

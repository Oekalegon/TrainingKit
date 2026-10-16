import Foundation

/// Checks a plan's projected `[FitnessMetrics]` against injury-risk and progress guardrails.
///
/// Pure functions over already-computed metrics — the MVP 2 generator loop is propose →
/// ``DailyLoadSeries`` → ``FitnessMetricsCalculator`` → `PlanEvaluator` → adjust → repeat until
/// ``PlanEvaluation/isAcceptable``, but MVP 1 already exposes this as a read-only "how does my
/// current plan look" check.
///
/// The metric rules (TSB band, monotony, strain, race-day TSB) always run, and the longest-run
/// rule runs on whatever `sessions` it is given. The three
/// paradigm rules (intensity distribution, hard-session spacing, hard sessions per micro) run
/// when a ``TrainingParadigm`` is supplied; see
/// ``evaluate(_:races:cycles:guardrails:sessions:paradigm:)``.
public struct PlanEvaluator: Sendable {
    /// Creates a plan evaluator.
    public init() {}

    /// Evaluates `metrics` (and, if supplied, `cycles`) against `guardrails`.
    ///
    /// - Parameters:
    ///   - metrics: The projected fitness series to evaluate. Must be gap-free and chronologically
    ///     ordered, as produced by ``FitnessMetricsCalculator``, so the rules don't re-derive day boundaries from a timezone
    ///     this type never receives.
    ///   - races: Races to check race-day TSB for. A race whose `date` doesn't match a day in
    ///     `metrics` exactly is skipped.
    ///   - cycles: The macro/meso/micro cycles the plan is laid out against, e.g. from
    ///     ``CycleLayoutBuilder``. Only the paradigm rules that read micros (hard sessions per micro,
    ///     intensity distribution) use them; the others run without.
    ///   - guardrails: The thresholds to check against; defaults to ``PlanGuardrails``'s defaults.
    ///     A supplied `paradigm`'s ``TrainingParadigm/guardrailOverrides`` are applied on top.
    ///   - sessions: The planned runs, day-granular in the same timezone as `metrics`: the
    ///     longest-run rule reads them, and so do the paradigm rules. Include the recent past runs
    ///     so a plan's first weeks have a longest run to compare with.
    ///   - paradigm: The training paradigm to check the plan against. Without one, the three
    ///     paradigm rules are skipped and the result is exactly as before paradigms existed.
    /// - Returns: Every finding from every rule that could run, in chronological order.
    public func evaluate(
        _ metrics: [FitnessMetrics],
        races: [Race],
        cycles: [TrainingCycle] = [],
        guardrails: PlanGuardrails = PlanGuardrails(),
        sessions: [PlanSession] = [],
        paradigm: TrainingParadigm? = nil
    ) -> PlanEvaluation {
        let guardrails = paradigm.map { $0.guardrailOverrides.applied(to: guardrails) } ?? guardrails

        // `uniquingKeysWith` rather than `uniqueKeysWithValues:` — the latter traps if `metrics`
        // ever contains two entries for the same day, which nothing here enforces against caller
        // input; keeping the later entry mirrors "last write wins" for any accidental duplicate.
        let metricsByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })

        var findings: [PlanFinding] = []
        findings += tsbBandFindings(metrics: metrics, guardrails: guardrails)
        findings += monotonyFindings(metrics: metrics, guardrails: guardrails)
        findings += strainFindings(metrics: metrics, guardrails: guardrails)
        findings += raceDayTSBFindings(metricsByDay: metricsByDay, races: races, guardrails: guardrails)

        findings += longestRunFindings(sessions: sessions, guardrails: guardrails)

        if let paradigm {
            findings += hardSessionSpacingFindings(sessions: sessions, paradigm: paradigm)
            if !cycles.isEmpty {
                findings += hardSessionsPerMicroFindings(sessions: sessions, cycles: cycles, paradigm: paradigm)
                findings += intensityDistributionFindings(sessions: sessions, cycles: cycles, paradigm: paradigm)
            }
        }

        return PlanEvaluation(findings: findings.sorted { $0.day < $1.day })
    }

    /// TSB per day, flagged when it drops below `minAcceptableTSB` (injury-risk territory) or
    /// climbs above `maxAcceptableTSB` (sustained freshness reading as detraining) — checked every
    /// day, unlike ``raceDayTSBFindings(metricsByDay:races:guardrails:)``, which only looks at a
    /// ``Race/date``. Warming-up days are skipped: CTL and ATL ramp up from zero at different
    /// rates regardless of the actual training load, so TSB means little until the series settles.
    private func tsbBandFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for entry in metrics where !entry.isWarmingUp {
            if entry.tsb < guardrails.minAcceptableTSB {
                findings.append(PlanFinding(day: entry.day, rule: .tsbBand, severity: .risk, value: entry.tsb, threshold: guardrails.minAcceptableTSB))
            } else if entry.tsb > guardrails.maxAcceptableTSB {
                findings.append(PlanFinding(day: entry.day, rule: .tsbBand, severity: .warning, value: entry.tsb, threshold: guardrails.maxAcceptableTSB))
            }
        }
        return findings
    }

    /// A day's monotony, flagged when it exceeds `maxMonotony`. `.nan` (a perfectly flat window,
    /// including a full rest week) is never flagged — see ``FitnessMetrics/monotony``.
    private func monotonyFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        metrics.compactMap { entry in
            guard !entry.monotony.isNaN, entry.monotony > guardrails.maxMonotony else { return nil }
            return PlanFinding(day: entry.day, rule: .monotony, severity: .risk, value: entry.monotony, threshold: guardrails.maxMonotony)
        }
    }

    /// A day's strain, flagged when it exceeds more of the trailing `strainTrailingWindowDays` of
    /// *prior* (non-`.nan`) strain values than `maxStrainPercentile` — today is never compared
    /// against itself, and ties don't count as "exceeding," so a perfectly flat run of identical
    /// strain values (e.g. a steady, unchanging week) never trivially ranks at its own 100th
    /// percentile. Skipped when there isn't enough trailing history yet to judge against.
    private func strainFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        let minimumSamples = 14
        var findings: [PlanFinding] = []
        for index in metrics.indices {
            let current = metrics[index]
            guard !current.strain.isNaN else { continue }

            let windowStart = max(0, index - guardrails.strainTrailingWindowDays)
            let priorHistory = metrics[windowStart..<index].map(\.strain).filter { !$0.isNaN }
            guard priorHistory.count >= minimumSamples else { continue }

            let percentile = Double(priorHistory.filter { $0 < current.strain }.count) / Double(priorHistory.count)
            if percentile > guardrails.maxStrainPercentile {
                findings.append(PlanFinding(day: current.day, rule: .strain, severity: .risk, value: percentile, threshold: guardrails.maxStrainPercentile))
            }
        }
        return findings
    }

    /// TSB on each race's date, flagged when it's below `minTSBOnRaceDay` (taper hasn't landed) or
    /// above `maxTSBOnRaceDay` (fitness was lost in the taper). A ``Severity/warning``, not a risk: a
    /// missed taper target is worth a second look but doesn't make the plan unsafe.
    private func raceDayTSBFindings(metricsByDay: [Date: FitnessMetrics], races: [Race], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for race in races {
            guard let entry = metricsByDay[race.date] else { continue }
            if entry.tsb < guardrails.minTSBOnRaceDay {
                findings.append(PlanFinding(day: race.date, rule: .raceDayTSB, severity: .warning, value: entry.tsb, threshold: guardrails.minTSBOnRaceDay))
            } else if entry.tsb > guardrails.maxTSBOnRaceDay {
                findings.append(PlanFinding(day: race.date, rule: .raceDayTSB, severity: .warning, value: entry.tsb, threshold: guardrails.maxTSBOnRaceDay))
            }
        }
        return findings
    }
}

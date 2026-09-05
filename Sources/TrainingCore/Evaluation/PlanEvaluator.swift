import Foundation

/// Checks a plan's projected `[FitnessMetrics]` against injury-risk and progress guardrails.
///
/// Pure functions over already-computed metrics — the MVP 2 generator loop is propose →
/// ``DailyLoadSeries`` → ``FitnessMetricsCalculator`` → `PlanEvaluator` → adjust → repeat until
/// ``PlanEvaluation/isAcceptable``, but MVP 1 already exposes this as a read-only "how does my
/// current plan look" check.
///
/// The cycle-free rules (CTL ramp, ATL/CTL ratio, monotony, strain, race-day TSB) always run.
/// Meso/micro-aware rules (recovery, build progression, meso progress, taper shape, consecutive
/// load) additionally run whenever `cycles` is non-empty; see
/// ``evaluate(_:races:cycles:guardrails:)``.
public struct PlanEvaluator: Sendable {
    /// Creates a plan evaluator.
    public init() {}

    /// Evaluates `metrics` (and, if supplied, `cycles`) against `guardrails`.
    ///
    /// - Parameters:
    ///   - metrics: The projected fitness series to evaluate. Must be gap-free and chronologically
    ///     ordered, as produced by ``FitnessMetricsCalculator`` — the CTL-ramp and consecutive-load
    ///     rules rely on this rather than re-deriving day boundaries from a timezone this type
    ///     never receives.
    ///   - races: Races to check race-day TSB for. A race whose `date` doesn't match a day in
    ///     `metrics` exactly is skipped.
    ///   - cycles: The macro/meso/micro cycles the plan is laid out against, e.g. from
    ///     ``CycleLayoutBuilder``. Without cycles, only the cycle-free rules run — the evaluator
    ///     never crashes or silently skips the rules that don't need cycles, it just can't run the
    ///     ones that do.
    ///   - guardrails: The thresholds to check against; defaults to ``PlanGuardrails``'s defaults.
    /// - Returns: Every finding from every rule that could run, in chronological order.
    public func evaluate(
        _ metrics: [FitnessMetrics],
        races: [Race],
        cycles: [TrainingCycle] = [],
        guardrails: PlanGuardrails = PlanGuardrails()
    ) -> PlanEvaluation {
        let metricsByDay = Dictionary(uniqueKeysWithValues: metrics.map { ($0.day, $0) })

        var findings: [PlanFinding] = []
        findings += ctlRampFindings(metrics: metrics, guardrails: guardrails)
        findings += atlToCTLRatioFindings(metrics: metrics, guardrails: guardrails)
        findings += monotonyFindings(metrics: metrics, guardrails: guardrails)
        findings += strainFindings(metrics: metrics, guardrails: guardrails)
        findings += raceDayTSBFindings(metricsByDay: metricsByDay, races: races, guardrails: guardrails)

        if !cycles.isEmpty {
            findings += recoveryMicroFindings(cycles: cycles, metrics: metrics, guardrails: guardrails)
            findings += buildProgressionFindings(cycles: cycles, metrics: metrics, guardrails: guardrails)
            findings += mesoProgressFindings(cycles: cycles, metricsByDay: metricsByDay, guardrails: guardrails)
            findings += taperShapeFindings(cycles: cycles, metricsByDay: metricsByDay, guardrails: guardrails)
            findings += consecutiveLoadFindings(cycles: cycles, guardrails: guardrails)
        }

        return PlanEvaluation(findings: findings.sorted { $0.day < $1.day })
    }

    /// CTL[d] − CTL[d−7] per day, flagged when it exceeds `maxCTLRampPerWeek`.
    private func ctlRampFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        guard metrics.count > 7 else { return [] }
        var findings: [PlanFinding] = []
        for index in 7..<metrics.count {
            let ramp = metrics[index].ctl - metrics[index - 7].ctl
            if ramp > guardrails.maxCTLRampPerWeek {
                findings.append(PlanFinding(day: metrics[index].day, rule: .ctlRamp, severity: .risk, value: ramp, threshold: guardrails.maxCTLRampPerWeek))
            }
        }
        return findings
    }

    /// ATL[d] / CTL[d] per day; exceeding the max is `.risk`, undershooting the min is `.warning`
    /// ("below this = detraining, not risk" per the guardrail's own documentation).
    private func atlToCTLRatioFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for entry in metrics where entry.ctl > 0 {
            let ratio = entry.atl / entry.ctl
            if ratio > guardrails.maxATLtoCTLRatio {
                findings.append(PlanFinding(day: entry.day, rule: .atlToCTLRatio, severity: .risk, value: ratio, threshold: guardrails.maxATLtoCTLRatio))
            } else if ratio < guardrails.minATLtoCTLRatio {
                findings.append(PlanFinding(day: entry.day, rule: .atlToCTLRatio, severity: .warning, value: ratio, threshold: guardrails.minATLtoCTLRatio))
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
    /// above `maxTSBOnRaceDay` (fitness was lost in the taper).
    private func raceDayTSBFindings(metricsByDay: [Date: FitnessMetrics], races: [Race], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for race in races {
            guard let entry = metricsByDay[race.date] else { continue }
            if entry.tsb < guardrails.minTSBOnRaceDay {
                findings.append(PlanFinding(day: race.date, rule: .raceDayTSB, severity: .risk, value: entry.tsb, threshold: guardrails.minTSBOnRaceDay))
            } else if entry.tsb > guardrails.maxTSBOnRaceDay {
                findings.append(PlanFinding(day: race.date, rule: .raceDayTSB, severity: .risk, value: entry.tsb, threshold: guardrails.maxTSBOnRaceDay))
            }
        }
        return findings
    }
}

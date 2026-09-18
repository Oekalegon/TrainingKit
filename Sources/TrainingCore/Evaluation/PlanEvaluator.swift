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
        // `uniquingKeysWith` rather than `uniqueKeysWithValues:` — the latter traps if `metrics`
        // ever contains two entries for the same day, which nothing here enforces against caller
        // input; keeping the later entry mirrors "last write wins" for any accidental duplicate.
        let metricsByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })

        var findings: [PlanFinding] = []
        findings += ctlRampFindings(metrics: metrics, guardrails: guardrails)
        findings += atlToCTLRatioFindings(metrics: metrics, guardrails: guardrails)
        findings += tsbBandFindings(metrics: metrics, guardrails: guardrails)
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

    /// CTL[d] − CTL[d−7] per day, flagged when it exceeds `maxCTLRampPerWeek`. Warming-up days are
    /// skipped — CTL mechanically ramps up from zero during warmup regardless of whether training
    /// load is actually excessive, so this would otherwise false-positive on every fresh series.
    private func ctlRampFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        guard metrics.count > 7 else { return [] }
        var findings: [PlanFinding] = []
        for index in 7..<metrics.count where !metrics[index].isWarmingUp {
            let ramp = metrics[index].ctl - metrics[index - 7].ctl
            if ramp > guardrails.maxCTLRampPerWeek {
                findings.append(PlanFinding(day: metrics[index].day, rule: .ctlRamp, severity: .risk, value: ramp, threshold: guardrails.maxCTLRampPerWeek))
            }
        }
        return findings
    }

    /// ATL[d] / CTL[d] per day; exceeding the max is `.risk`, undershooting the min is `.warning`
    /// ("below this = detraining, not risk" per the guardrail's own documentation). Warming-up days
    /// are skipped — ATL (τ=7) ramps faster than CTL (τ=42) from a cold start, inflating the ratio
    /// independent of the actual training load. Days below `minCTLForRatioCheck` are skipped by
    /// `bandFindings` returning `nil` for them (which also covers a zero-CTL day, avoiding the
    /// divide-by-zero, without needing a separate check): the ratio is hypersensitive at a low
    /// absolute CTL — see `minCTLForRatioCheck`'s own doc comment.
    private func atlToCTLRatioFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        bandFindings(
            metrics: metrics, rule: .atlToCTLRatio,
            value: { $0.ctl >= guardrails.minCTLForRatioCheck ? $0.atl / $0.ctl : nil },
            lowerBound: guardrails.minATLtoCTLRatio, lowerSeverity: .warning,
            upperBound: guardrails.maxATLtoCTLRatio, upperSeverity: .risk
        )
    }

    /// TSB per day, flagged when it drops below `minAcceptableTSB` (injury-risk territory) or
    /// climbs above `maxAcceptableTSB` (sustained freshness reading as detraining) — the direct
    /// freshness/fatigue signal, unlike ``atlToCTLRatioFindings(metrics:guardrails:)``'s ratio
    /// proxy, and checked every day rather than only on a ``Race/date`` like
    /// ``raceDayTSBFindings(metricsByDay:races:guardrails:)``. Warming-up days are skipped for the
    /// same cold-start reason as the ratio check.
    private func tsbBandFindings(metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        bandFindings(
            metrics: metrics, rule: .tsbBand, value: { $0.tsb },
            lowerBound: guardrails.minAcceptableTSB, lowerSeverity: .risk,
            upperBound: guardrails.maxAcceptableTSB, upperSeverity: .warning
        )
    }

    /// Shared shape behind ``atlToCTLRatioFindings(metrics:guardrails:)`` and
    /// ``tsbBandFindings(metrics:guardrails:)``: a per-day scalar checked against a two-sided band,
    /// skipping warming-up days. The two callers otherwise differed only in which scalar they read,
    /// which side of the band is `.risk` vs `.warning`, and (for the ratio) an extra zero-CTL guard
    /// before dividing — folded here into `value` returning `nil` to skip a day outright.
    ///
    /// - Parameters:
    ///   - value: The day's value to check, or `nil` to skip that day entirely (e.g. a zero-CTL day
    ///     for the ATL/CTL ratio).
    ///   - lowerBound: Below this fires `lowerSeverity`.
    ///   - upperBound: Above this fires `upperSeverity`. Checked first, so `lowerBound > upperBound`
    ///     would silently only ever fire the upper side — every caller's bounds are a real band
    ///     (`lowerBound < upperBound`), so this never arises in practice.
    private func bandFindings(
        metrics: [FitnessMetrics],
        rule: PlanRule,
        value: (FitnessMetrics) -> Double?,
        lowerBound: Double,
        lowerSeverity: Severity,
        upperBound: Double,
        upperSeverity: Severity
    ) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for entry in metrics where !entry.isWarmingUp {
            guard let value = value(entry) else { continue }
            if value > upperBound {
                findings.append(PlanFinding(day: entry.day, rule: rule, severity: upperSeverity, value: value, threshold: upperBound))
            } else if value < lowerBound {
                findings.append(PlanFinding(day: entry.day, rule: rule, severity: lowerSeverity, value: value, threshold: lowerBound))
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

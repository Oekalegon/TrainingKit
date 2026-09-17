import Foundation

/// The `cycles`-dependent rules from design doc §10.4, split out of the main file since they only
/// run when the caller supplies cycles (see ``PlanEvaluator/evaluate(_:races:cycles:guardrails:)``).
extension PlanEvaluator {
    /// A recovery-phase micro's total load relative to the micro immediately before it, flagged
    /// when it exceeds `recoveryLoadFraction` — i.e. the recovery micro didn't actually recover.
    func recoveryMicroFindings(cycles: [TrainingCycle], metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        let micros = sortedMicros(cycles)
        var findings: [PlanFinding] = []
        for (previous, current) in zip(micros, micros.dropFirst()) where current.phase == .recovery {
            let previousLoad = totalLoad(in: previous.dateRange, metrics: metrics)
            guard previousLoad > 0 else { continue }
            let recoveryLoad = totalLoad(in: current.dateRange, metrics: metrics)
            let fraction = recoveryLoad / previousLoad
            if fraction > guardrails.recoveryLoadFraction {
                findings.append(PlanFinding(day: current.dateRange.lowerBound, rule: .recoveryMicro, severity: .risk, value: fraction, threshold: guardrails.recoveryLoadFraction))
            }
        }
        return findings
    }

    /// A build-phase micro's total load relative to the previous build-phase micro (skipping over
    /// any recovery micros in between). Below 0% is ``Severity/info`` (the plan isn't building, but
    /// that alone isn't a trend worth a second look); above `maxBuildProgressionFraction` is
    /// ``Severity/risk`` (too aggressive a jump).
    func buildProgressionFindings(cycles: [TrainingCycle], metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        var previousBuildLoad: Double?
        for micro in sortedMicros(cycles) where micro.phase == .build {
            let load = totalLoad(in: micro.dateRange, metrics: metrics)
            defer { previousBuildLoad = load }

            guard let previousLoad = previousBuildLoad, previousLoad > 0 else { continue }
            let fraction = (load - previousLoad) / previousLoad
            if fraction < 0 {
                findings.append(PlanFinding(day: micro.dateRange.lowerBound, rule: .buildProgression, severity: .info, value: fraction, threshold: 0))
            } else if fraction > guardrails.maxBuildProgressionFraction {
                findings.append(PlanFinding(day: micro.dateRange.lowerBound, rule: .buildProgression, severity: .risk, value: fraction, threshold: guardrails.maxBuildProgressionFraction))
            }
        }
        return findings
    }

    /// CTL gain across a base/build meso, flagged when it falls short of `minCTLGainPerMeso` — a
    /// "safe" plan that's actually flat. Skipped if either boundary day is still warming up, since
    /// CTL there hasn't settled enough to make "gain" meaningful.
    func mesoProgressFindings(cycles: [TrainingCycle], metricsByDay: [Date: FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        cycles.filter { $0.level == .meso && ($0.phase == .base || $0.phase == .build) }.compactMap { meso in
            guard let start = metricsByDay[meso.dateRange.lowerBound],
                  let end = metricsByDay[meso.dateRange.upperBound],
                  !start.isWarmingUp, !end.isWarmingUp
            else { return nil }
            let gain = end.ctl - start.ctl
            guard gain < guardrails.minCTLGainPerMeso else { return nil }
            return PlanFinding(day: meso.dateRange.lowerBound, rule: .mesoProgress, severity: .risk, value: gain, threshold: guardrails.minCTLGainPerMeso)
        }
    }

    /// CTL drop across a taper meso (flagged past `maxTaperCTLDropFraction`) and whether TSB
    /// actually rose across it (flagged if it didn't) — "taper landed: positive but not so high
    /// that fitness was lost." The two checks are independent: a missing/zero CTL precondition for
    /// the drop check doesn't suppress the TSB check, which doesn't depend on CTL at all. Skipped
    /// if either boundary day is still warming up.
    func taperShapeFindings(cycles: [TrainingCycle], metricsByDay: [Date: FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for meso in cycles where meso.level == .meso && meso.phase == .taper {
            guard let start = metricsByDay[meso.dateRange.lowerBound],
                  let end = metricsByDay[meso.dateRange.upperBound],
                  !start.isWarmingUp, !end.isWarmingUp
            else { continue }

            if start.ctl > 0 {
                let dropFraction = (start.ctl - end.ctl) / start.ctl
                if dropFraction > guardrails.maxTaperCTLDropFraction {
                    findings.append(PlanFinding(day: meso.dateRange.lowerBound, rule: .taperShape, severity: .risk, value: dropFraction, threshold: guardrails.maxTaperCTLDropFraction))
                }
            }

            let tsbRise = end.tsb - start.tsb
            if tsbRise <= 0 {
                findings.append(PlanFinding(day: meso.dateRange.lowerBound, rule: .taperShape, severity: .warning, value: tsbRise, threshold: 0))
            }
        }
        return findings
    }

    /// The number of consecutive non-recovery micros since the last recovery-phase micro, flagged
    /// once it exceeds `maxMicrosWithoutRecovery` — "you've gone N weeks without a rest week."
    func consecutiveLoadFindings(cycles: [TrainingCycle], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        var consecutiveCount = 0
        for micro in sortedMicros(cycles) {
            if micro.phase == .recovery {
                consecutiveCount = 0
                continue
            }
            consecutiveCount += 1
            if consecutiveCount > guardrails.maxMicrosWithoutRecovery {
                findings.append(
                    PlanFinding(
                        day: micro.dateRange.lowerBound,
                        rule: .consecutiveLoad,
                        severity: .risk,
                        value: Double(consecutiveCount),
                        threshold: Double(guardrails.maxMicrosWithoutRecovery)
                    )
                )
            }
        }
        return findings
    }

    /// Micro-level cycles, chronologically ordered.
    private func sortedMicros(_ cycles: [TrainingCycle]) -> [TrainingCycle] {
        cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
    }

    /// The sum of `metrics[].load` for every day within `range`, matched by exact `Date` equality
    /// rather than calendar arithmetic — sidesteps needing a timezone `PlanEvaluator` never
    /// receives, since `range` and `metrics[].day` are both already day-granular in the same
    /// (athlete) timezone by the time they reach here.
    private func totalLoad(in range: ClosedRange<Date>, metrics: [FitnessMetrics]) -> Double {
        metrics.filter { range.contains($0.day) }.reduce(0) { $0 + $1.load }
    }
}

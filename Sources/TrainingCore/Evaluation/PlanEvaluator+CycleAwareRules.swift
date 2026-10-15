import Foundation

/// The `cycles`-dependent rule from design doc §10.4, split out of the main file since it only
/// runs when the caller supplies cycles (see ``PlanEvaluator/evaluate(_:races:cycles:guardrails:)``).
extension PlanEvaluator {
    /// A build-phase micro's mean daily load relative to the previous build-phase micro (skipping over
    /// any recovery micros in between). Below 0% is ``Severity/info`` (the plan isn't building, but
    /// that alone isn't a trend worth a second look); above `maxBuildProgressionFraction` is
    /// ``Severity/risk`` (too aggressive a jump).
    func buildProgressionFindings(cycles: [TrainingCycle], metrics: [FitnessMetrics], guardrails: PlanGuardrails) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        var previousBuildLoad: Double?
        for micro in sortedMicros(cycles) where micro.phase == .build {
            let load = meanDailyLoad(in: micro.dateRange, metrics: metrics)
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

    /// Micro-level cycles, chronologically ordered.
    private func sortedMicros(_ cycles: [TrainingCycle]) -> [TrainingCycle] {
        cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
    }

    /// The mean of `metrics[].load` over the days of `range` that `metrics` covers, matched by exact
    /// `Date` equality rather than calendar arithmetic — sidesteps needing a timezone
    /// `PlanEvaluator` never receives, since `range` and `metrics[].day` are both already
    /// day-granular in the same (athlete) timezone by the time they reach here. Days the series
    /// doesn't cover (a micro running past the end of the projection) are left out of the mean
    /// rather than counted as zero load; a micro with no covered day has a mean of zero.
    private func meanDailyLoad(in range: ClosedRange<Date>, metrics: [FitnessMetrics]) -> Double {
        let covered = metrics.filter { range.contains($0.day) }
        guard !covered.isEmpty else { return 0 }
        return covered.reduce(0) { $0 + $1.load } / Double(covered.count)
    }
}

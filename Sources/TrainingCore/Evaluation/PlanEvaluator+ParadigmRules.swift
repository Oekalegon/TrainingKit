import Foundation

/// The paradigm rules, split out of the main file since they only run when the caller supplies a
/// ``TrainingParadigm`` (see ``PlanEvaluator/evaluate(_:races:cycles:guardrails:sessions:paradigm:)``).
extension PlanEvaluator {
    private static let secondsPerDay: TimeInterval = 86_400
    /// Slack for comparing shares that are sums of floating-point fractions against a bound.
    private static let shareEpsilon = 1e-9

    /// Two hard sessions closer together than ``TrainingParadigm/minDaysBetweenHardSessions``.
    ///
    /// Compares each hard session with the previous one in date order, so two on the same day
    /// (0 days apart) fail any minimum of 1 or more. A ``Severity/risk`` dated at the later
    /// session; `value` is the days between the two, `threshold` the minimum. Gaps are whole
    /// calendar days, rounded, so a daylight-saving day does not change the count.
    func hardSessionSpacingFindings(sessions: [PlanSession], paradigm: TrainingParadigm) -> [PlanFinding] {
        guard let minimum = paradigm.minDaysBetweenHardSessions else { return [] }
        let hard = sessions.filter(paradigm.isHard).sorted { $0.day < $1.day }
        var findings: [PlanFinding] = []
        for (previous, current) in zip(hard, hard.dropFirst()) {
            let gap = Int((current.day.timeIntervalSince(previous.day) / Self.secondsPerDay).rounded())
            if gap < minimum {
                findings.append(PlanFinding(day: current.day, rule: .hardSessionSpacing, severity: .risk, value: Double(gap), threshold: Double(minimum)))
            }
        }
        return findings
    }

    /// A micro with more hard sessions than ``TrainingParadigm/maxHardSessionsPerMicro`` allows
    /// for its length in days. A ``Severity/risk`` dated at the micro's start; `value` is the
    /// count, `threshold` the maximum. Micros whose length has no entry are not checked.
    func hardSessionsPerMicroFindings(sessions: [PlanSession], cycles: [TrainingCycle], paradigm: TrainingParadigm) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for micro in micros(cycles) {
            guard let maximum = paradigm.maxHardSessionsPerMicro[length(of: micro)] else { continue }
            let count = sessions.filter { micro.dateRange.contains($0.day) && paradigm.isHard($0) }.count
            if count > maximum {
                findings.append(PlanFinding(day: micro.dateRange.lowerBound, rule: .hardSessionsPerMicro, severity: .risk, value: Double(count), threshold: Double(maximum)))
            }
        }
        return findings
    }

    /// The share of each micro's planned time per intensity category and speed level, against the
    /// target of the micro's phase (``TrainingParadigm/phaseMixes``, else ``TrainingParadigm/defaultMix``).
    ///
    /// A ``Severity/warning`` dated at the micro's start for every listed category or level whose
    /// share is further than the mix's tolerance from its target; `value` is the actual share and
    /// `threshold` the nearest bound (target ± tolerance) it crosses. A share exactly at the
    /// tolerance passes. Micros with no sessions, or no planned time, are not checked.
    func intensityDistributionFindings(sessions: [PlanSession], cycles: [TrainingCycle], paradigm: TrainingParadigm) -> [PlanFinding] {
        var findings: [PlanFinding] = []
        for micro in micros(cycles) {
            guard let mix = paradigm.phaseMixes[micro.phase] ?? paradigm.defaultMix else { continue }
            let inMicro = sessions.filter { micro.dateRange.contains($0.day) }
            let total = inMicro.reduce(0) { $0 + $1.seconds }
            guard total > 0 else { continue }

            func check(target: Double, actual: Double) {
                let deviation = actual - target
                guard abs(deviation) > mix.tolerance + Self.shareEpsilon else { return }
                let bound = deviation > 0 ? target + mix.tolerance : target - mix.tolerance
                findings.append(PlanFinding(day: micro.dateRange.lowerBound, rule: .intensityDistribution, severity: .warning, value: actual, threshold: bound))
            }
            for category in IntensityCategory.allCases {
                guard let target = mix.intensityShares[category] else { continue }
                check(target: target, actual: inMicro.filter { $0.intensity == category }.reduce(0) { $0 + $1.seconds } / total)
            }
            for level in SpeedLevel.allCases {
                guard let target = mix.speedShares[level] else { continue }
                check(target: target, actual: inMicro.filter { $0.speed == level }.reduce(0) { $0 + $1.seconds } / total)
            }
        }
        return findings
    }

    private func micros(_ cycles: [TrainingCycle]) -> [TrainingCycle] {
        cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
    }

    /// The micro's length in whole calendar days, rounded so a daylight-saving day does not change it.
    private func length(of micro: TrainingCycle) -> Int {
        Int((micro.dateRange.upperBound.timeIntervalSince(micro.dateRange.lowerBound) / Self.secondsPerDay).rounded()) + 1
    }
}

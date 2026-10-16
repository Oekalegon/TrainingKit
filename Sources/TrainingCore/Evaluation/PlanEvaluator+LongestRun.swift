import Foundation

extension PlanEvaluator {
    private static let secondsPerDay: TimeInterval = 86_400
    private static let fractionEpsilon = 1e-9

    /// A run longer than the longest run of the previous ``PlanGuardrails/longestRunLookBackDays`` days (28 by default) by more
    /// than ``PlanGuardrails/maxLongestRunIncreaseFraction``.
    ///
    /// Every session counts as a run, of any type, and is compared by planned duration with the
    /// longest session from the look-back before its day (the day itself is not part of the look-back).
    /// A session with no run in that look-back is not checked. A ``Severity/risk`` dated at the
    /// session; `value` is the fractional increase and `threshold` the limit. Each run is judged
    /// against the earlier runs of the plan, so a chain of runs each within the limit of the last
    /// is allowed. Day gaps are whole calendar days, rounded, so a daylight-saving day does not
    /// shift the window.
    func longestRunFindings(sessions: [PlanSession], guardrails: PlanGuardrails) -> [PlanFinding] {
        let ordered = sessions.filter { $0.seconds > 0 }.sorted { $0.day < $1.day }
        var findings: [PlanFinding] = []
        for (index, run) in ordered.enumerated() {
            // Walk back from the run and stop once past the look-back: `ordered` is by day.
            var longest: TimeInterval?
            for other in ordered[..<index].reversed() {
                let gap = Int((run.day.timeIntervalSince(other.day) / Self.secondsPerDay).rounded())
                if gap > guardrails.longestRunLookBackDays { break }
                if gap >= 1 { longest = max(longest ?? 0, other.seconds) }
            }
            guard let longest else { continue }
            let increase = (run.seconds - longest) / longest
            if increase > guardrails.maxLongestRunIncreaseFraction + Self.fractionEpsilon {
                findings.append(PlanFinding(day: run.day, rule: .longestRun, severity: .risk, value: increase, threshold: guardrails.maxLongestRunIncreaseFraction))
            }
        }
        return findings
    }
}

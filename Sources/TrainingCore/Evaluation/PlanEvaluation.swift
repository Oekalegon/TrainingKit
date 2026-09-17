/// The result of running ``PlanEvaluator/evaluate(_:races:cycles:guardrails:)``.
public struct PlanEvaluation: Sendable, Hashable {
    /// Every guardrail observation from the evaluation, in chronological order.
    public let findings: [PlanFinding]

    /// `true` unless at least one finding is ``Severity/risk``.
    public var isAcceptable: Bool {
        !findings.contains { $0.severity == .risk }
    }

    /// Creates a plan evaluation.
    ///
    /// - Parameter findings: Every guardrail observation from the evaluation.
    public init(findings: [PlanFinding]) {
        self.findings = findings
    }
}

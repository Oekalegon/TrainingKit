/// How urgently a ``PlanFinding`` should be acted on.
public enum Severity: Sendable, Codable, Hashable {
    /// Worth surfacing, not worth blocking on — e.g. a build micro that didn't gain as much load
    /// as expected.
    case info
    /// A real concern that should prompt a second look, but isn't itself injury-risk — e.g. the
    /// plan is losing fitness (``PlanGuardrails/minATLtoCTLRatio`` undershot).
    case warning
    /// Injury-risk or plan-breaking; ``PlanEvaluation/isAcceptable`` is `false` whenever any
    /// finding has this severity.
    case risk
}

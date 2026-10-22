import Foundation

/// One guardrail observation from ``PlanEvaluator``.
public struct PlanFinding: Sendable, Codable, Hashable {
    /// The day this finding applies to — the day the rule's signal was computed for, or the start
    /// of the relevant cycle for a cycle-aware rule.
    public let day: Date
    /// Which guardrail produced this finding.
    public let rule: PlanRule
    /// How urgently this should be acted on.
    public let severity: Severity
    /// The computed signal value that triggered this finding.
    public let value: Double
    /// The guardrail threshold `value` was compared against.
    public let threshold: Double
    /// What within the rule the finding is about, when a rule checks several things at once: for
    /// ``PlanRule/intensityDistribution`` the intensity category or speed level that missed its
    /// share (`"intensity.high"`, `"speed.max"`); `nil` for every other rule.
    public let subject: String?

    /// Creates a plan finding.
    ///
    /// - Parameters:
    ///   - day: The day this finding applies to.
    ///   - rule: Which guardrail produced this finding.
    ///   - severity: How urgently this should be acted on.
    ///   - value: The computed signal value that triggered this finding.
    ///   - threshold: The guardrail threshold `value` was compared against.
    ///   - subject: What within the rule the finding is about; defaults to `nil`.
    public init(day: Date, rule: PlanRule, severity: Severity, value: Double, threshold: Double, subject: String? = nil) {
        self.day = day
        self.rule = rule
        self.severity = severity
        self.value = value
        self.threshold = threshold
        self.subject = subject
    }
}

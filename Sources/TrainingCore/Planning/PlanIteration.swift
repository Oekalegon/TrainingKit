import Foundation

/// One adjustment ``PlanAdjuster`` tried, and what it did to the risks.
public struct PlanIteration: Sendable, Codable, Hashable {
    /// What was tried.
    public var adjustment: PlanAdjustment
    /// The rule of the risk finding it was meant to answer.
    public var answering: PlanRule
    /// The number of ``Severity/risk`` findings before.
    public var risksBefore: Int
    /// The number of ``Severity/risk`` findings after.
    public var risksAfter: Int
    /// Whether the adjustment was kept: it lowered the number of risks, or kept it and moved the
    /// risks closer to their thresholds.
    public var kept: Bool

    /// Creates an iteration.
    ///
    /// - Parameters:
    ///   - adjustment: What was tried.
    ///   - answering: The rule of the risk it was meant to answer.
    ///   - risksBefore: The number of risks before.
    ///   - risksAfter: The number of risks after.
    ///   - kept: Whether the adjustment was kept.
    public init(adjustment: PlanAdjustment, answering: PlanRule, risksBefore: Int, risksAfter: Int, kept: Bool) {
        self.adjustment = adjustment
        self.answering = answering
        self.risksBefore = risksBefore
        self.risksAfter = risksAfter
        self.kept = kept
    }
}

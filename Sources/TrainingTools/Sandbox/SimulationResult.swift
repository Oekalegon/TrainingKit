import TrainingCore

/// The result of ``PlanSandbox/simulate(engine:evaluator:)``: the projected fitness series over
/// the sandbox's current working set, and what ``PlanEvaluator`` makes of it.
public struct SimulationResult: Sendable, Equatable {
    /// The projected day-by-day fitness series over the sandbox's current working set.
    public let metrics: [FitnessMetrics]
    /// What ``PlanEvaluator`` makes of `metrics` against the guardrails `simulate` was called with.
    public let evaluation: PlanEvaluation

    public init(metrics: [FitnessMetrics], evaluation: PlanEvaluation) {
        self.metrics = metrics
        self.evaluation = evaluation
    }
}

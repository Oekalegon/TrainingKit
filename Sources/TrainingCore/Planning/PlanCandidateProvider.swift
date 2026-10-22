import Foundation

/// Builds the plan for a set of ``PlanLevers``: the seam where the plan generator plugs into
/// ``PlanAdjuster`` (MVP5-120).
///
/// The generator composes ``CycleLayoutBuilder``, ``VolumeCurveBuilder``, ``DayAssigner``,
/// ``TemplateFitter`` and ``StepTargetResolver``, applies the levers, and projects the series. Tests
/// use a stub.
public protocol PlanCandidateProvider: Sendable {
    /// Builds the plan with `levers` applied.
    ///
    /// - Parameters:
    ///   - levers: The changes to apply; ``PlanLevers/none`` for the first plan.
    ///   - today: The current day, passed through by the caller so the plan does not read the clock.
    /// - Returns: The plan with its projected metrics.
    func candidate(levers: PlanLevers, today: Date) async throws -> PlanCandidate
}

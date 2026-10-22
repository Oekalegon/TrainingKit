import Foundation

/// A plan as a ``PlanCandidateProvider`` built it, before ``PlanAdjuster`` evaluates it (MVP5-120).
public struct PlanCandidate: Sendable, Codable, Hashable {
    /// The macro, meso and micro cycles the plan is laid out on.
    public var cycles: [TrainingCycle]
    /// The planned workouts, from the first to the last day of the plan.
    public var plannedActivities: [PlannedActivity]
    /// The same runs as ``PlanEvaluator`` sees them, day-granular in the timezone of `metrics`;
    /// include recent past runs so the first weeks have a longest run to compare with.
    public var sessions: [PlanSession]
    /// The projected fitness series with the plan in it (``DailyLoadSeries`` and
    /// ``FitnessMetricsCalculator``), gap-free and chronological.
    public var metrics: [FitnessMetrics]
    /// What the provider gave up building the plan: lead time, unplaced sessions, missing templates,
    /// overridden preferences.
    public var compromises: [PlanCompromise]

    /// Creates a candidate.
    ///
    /// - Parameters:
    ///   - cycles: The cycles the plan is laid out on.
    ///   - plannedActivities: The planned workouts.
    ///   - sessions: The planned runs as ``PlanEvaluator`` sees them.
    ///   - metrics: The projected fitness series.
    ///   - compromises: What the provider gave up; defaults to none.
    public init(
        cycles: [TrainingCycle],
        plannedActivities: [PlannedActivity],
        sessions: [PlanSession],
        metrics: [FitnessMetrics],
        compromises: [PlanCompromise] = []
    ) {
        self.cycles = cycles
        self.plannedActivities = plannedActivities
        self.sessions = sessions
        self.metrics = metrics
        self.compromises = compromises
    }
}

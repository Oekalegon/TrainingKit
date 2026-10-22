import Foundation

/// A plan as a ``PlanCandidateProvider`` built it, before ``PlanAdjuster`` evaluates it (MVP5-120).
public struct PlanCandidate: Sendable, Codable, Hashable {
    /// The macro, meso and micro cycles the plan is laid out on.
    public var cycles: [TrainingCycle]
    /// The planned workouts, from the first to the last day of the plan.
    public var plannedActivities: [PlannedActivity]
    /// The workouts the planned workouts refer to (``PlannedActivity/workoutID``), as the template
    /// fitter made them; committing a proposal saves them to the workout library.
    public var workouts: [StructuredWorkout]
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
    ///   - workouts: The workouts they refer to; defaults to none.
    ///   - sessions: The planned runs as ``PlanEvaluator`` sees them.
    ///   - metrics: The projected fitness series.
    ///   - compromises: What the provider gave up; defaults to none.
    public init(
        cycles: [TrainingCycle],
        plannedActivities: [PlannedActivity],
        workouts: [StructuredWorkout] = [],
        sessions: [PlanSession],
        metrics: [FitnessMetrics],
        compromises: [PlanCompromise] = []
    ) {
        self.cycles = cycles
        self.plannedActivities = plannedActivities
        self.workouts = workouts
        self.sessions = sessions
        self.metrics = metrics
        self.compromises = compromises
    }
}

extension PlanCandidate {
    private enum CodingKeys: String, CodingKey {
        case cycles, plannedActivities, workouts, sessions, metrics, compromises
    }

    /// Decodes a candidate; `workouts` is optional and defaults to none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cycles = try container.decode([TrainingCycle].self, forKey: .cycles)
        plannedActivities = try container.decode([PlannedActivity].self, forKey: .plannedActivities)
        workouts = try container.decodeIfPresent([StructuredWorkout].self, forKey: .workouts) ?? []
        sessions = try container.decode([PlanSession].self, forKey: .sessions)
        metrics = try container.decode([FitnessMetrics].self, forKey: .metrics)
        compromises = try container.decode([PlanCompromise].self, forKey: .compromises)
    }
}

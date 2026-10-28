import Foundation
import TrainingCore

/// Turns a set of activities/plans/workouts into a projected `[FitnessMetrics]` series, the way
/// ``PlanSandbox/simulate(engine:evaluator:today:guardrails:)`` needs to without hard-coding one
/// particular `LoadCalculator`/`PlannedLoadEstimator` choice.
public protocol SeriesEngine: Sendable {
    /// The projected fitness series for a working set.
    ///
    /// - Parameters:
    ///   - activities: Completed activities.
    ///   - plans: Planned activities.
    ///   - workouts: The library workouts `plans` reference.
    ///   - races: The races whose load is added on their day, from `today` on, like `TrainingModel` does
    ///     (MVP5-149); a race adds its load whatever its priority.
    ///   - athlete: Supplies the time zone, zones and pace model.
    ///   - today: The boundary between actual and projected days.
    /// - Returns: One `FitnessMetrics` per day.
    func metrics(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        races: [Race],
        athlete: AthleteProfile,
        today: Date
    ) -> [FitnessMetrics]
}

/// The MVP 1 ``SeriesEngine``: ``DailyLoadSeries`` fed by ``TRIMPPlanEstimator`` for planned
/// activities and, per completed activity, the first of ``ExponentialTRIMPCalculator`` (needs
/// heart-rate) or ``DurationRPECalculator`` (needs perceived exertion) to succeed — then
/// ``FitnessMetricsCalculator`` over the result. No seed: as with any unseeded series, the first
/// `parameters.ctlTimeConstantDays` days come back `isWarmingUp`.
public struct DefaultSeriesEngine: SeriesEngine {
    private let series = DailyLoadSeries()
    private let calculator = FitnessMetricsCalculator()
    private let estimator: PlannedLoadEstimator
    private let loadCalculators: [any LoadCalculator]
    private let parameters: LoadModelParameters

    /// Creates the engine.
    ///
    /// - Parameters:
    ///   - estimator: Estimates the load of planned activities and races; defaults to `TRIMPPlanEstimator`.
    ///   - loadCalculators: Tried in order per completed activity.
    ///   - parameters: The CTL/ATL time constants.
    public init(
        estimator: PlannedLoadEstimator = TRIMPPlanEstimator(),
        loadCalculators: [any LoadCalculator] = [ExponentialTRIMPCalculator(), ImportedLoadCalculator(), DurationRPECalculator()],
        parameters: LoadModelParameters = LoadModelParameters()
    ) {
        self.estimator = estimator
        self.loadCalculators = loadCalculators
        self.parameters = parameters
    }

    public func metrics(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        races: [Race],
        athlete: AthleteProfile,
        today: Date
    ) -> [FitnessMetrics] {
        let days = series.days(
            activities: activities,
            plans: plans,
            workouts: workouts,
            races: races,
            estimator: estimator,
            calculators: loadCalculators,
            athlete: athlete,
            today: today
        )
        return calculator.metrics(for: days, parameters: parameters, seed: nil)
    }
}

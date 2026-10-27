import Foundation
import TrainingCore

/// Turns a set of activities/plans/workouts into a projected `[FitnessMetrics]` series, the way
/// ``PlanSandbox/simulate(engine:evaluator:today:guardrails:)`` needs to without hard-coding one
/// particular `LoadCalculator`/`PlannedLoadEstimator` choice.
public protocol SeriesEngine: Sendable {
    func metrics(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
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
    private let races: [Race]

    /// Creates the engine.
    ///
    /// - Parameters:
    ///   - estimator: Estimates the load of planned activities and races; defaults to `TRIMPPlanEstimator`.
    ///   - loadCalculators: Tried in order per completed activity.
    ///   - parameters: The CTL/ATL time constants.
    ///   - races: The races whose load is added on their day, like `TrainingModel` does; defaults to
    ///     none. The engine's ``metrics(activities:plans:workouts:athlete:today:)`` has no races
    ///     argument, so pass the athlete's races here when the sandbox should show the same series.
    public init(
        estimator: PlannedLoadEstimator = TRIMPPlanEstimator(),
        loadCalculators: [any LoadCalculator] = [ExponentialTRIMPCalculator(), ImportedLoadCalculator(), DurationRPECalculator()],
        parameters: LoadModelParameters = LoadModelParameters(),
        races: [Race] = []
    ) {
        self.races = races
        self.estimator = estimator
        self.loadCalculators = loadCalculators
        self.parameters = parameters
    }

    public func metrics(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
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

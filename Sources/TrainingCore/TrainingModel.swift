import Foundation

/// The observable facade the app builds its UI on: owns the current activities/plans/workouts/
/// cycles/metrics, and keeps them in sync with the stores.
///
/// `cycleStats`/`evaluation` (design doc §3.3) and `importActivities(from:)` aren't implemented
/// yet — they depend on ``TrainingCore``'s periodisation-statistics, plan-evaluator, and
/// `TrainingHealthKit` adapter work, none of which exist yet. They'll be added as small,
/// additive extensions once those land.
@Observable
@MainActor
public final class TrainingModel {
    public private(set) var activities: [Activity] = []
    public private(set) var plans: [PlannedActivity] = []
    public private(set) var workouts: [StructuredWorkout] = []
    public private(set) var cycles: [TrainingCycle] = []
    public private(set) var metrics: [FitnessMetrics] = []
    /// The athlete this model reflects. A plain, caller-managed property — `TrainingModel` doesn't
    /// automatically load or save it via `AthleteStore`.
    public var athlete: AthleteProfile
    /// EWMA time constants and monotony window used by ``recompute(asOf:)``.
    public var parameters: LoadModelParameters

    private let stores: StoreSet
    private let estimator: any PlannedLoadEstimator
    private let calculators: [any LoadCalculator]
    private var loadedRange: ClosedRange<Date>?

    /// Creates a training model.
    ///
    /// - Parameters:
    ///   - stores: Where activities/plans/workouts/cycles/the athlete profile are persisted.
    ///   - athlete: The athlete this model reflects.
    ///   - parameters: EWMA time constants and monotony window; defaults to the standard values.
    ///   - estimator: Estimates load for planned activities; defaults to ``TRIMPPlanEstimator``.
    ///   - calculators: Tried in order per activity; defaults to
    ///     ``ExponentialTRIMPCalculator``/``DurationRPECalculator``.
    public init(
        stores: StoreSet,
        athlete: AthleteProfile,
        parameters: LoadModelParameters = LoadModelParameters(),
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        calculators: [any LoadCalculator] = [ExponentialTRIMPCalculator(), DurationRPECalculator()]
    ) {
        self.stores = stores
        self.athlete = athlete
        self.parameters = parameters
        self.estimator = estimator
        self.calculators = calculators
    }

    /// Fetches activities/plans/cycles in `range` and the full workout library from the stores,
    /// then recomputes. Call once at startup, and again if the visible range changes.
    ///
    /// Fetches into locals first and only assigns once all four succeed, so a failure partway
    /// through (e.g. the plan fetch throwing after the activity fetch already succeeded) leaves
    /// this model exactly as it was before the call, rather than a mix of the old and new range.
    public func load(in range: ClosedRange<Date>, asOf today: Date = .now) async throws {
        let newActivities = try await stores.activityStore.activities(in: range)
        let newPlans = try await stores.planStore.plans(in: range)
        let newWorkouts = try await stores.workoutStore.workouts()
        let newCycles = try await stores.cycleStore.cycles(in: range)

        activities = newActivities
        plans = newPlans
        workouts = newWorkouts
        cycles = newCycles
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Upserts `plan` into ``PlanStore``, reloads plans and the workout library from the store,
    /// and recomputes.
    ///
    /// If ``load(in:asOf:)`` hasn't been called yet, this falls back to a range covering just
    /// `plan.date` (and adopts it as the loaded range) rather than silently skipping the reload —
    /// without this, the plan would persist to the store but `plans`/`metrics` would never reflect
    /// it, with no error to signal anything was skipped.
    public func add(_ plan: PlannedActivity, asOf today: Date = .now) async throws {
        try await stores.planStore.upsert([plan])
        let range = loadedRange ?? (plan.date...plan.date)
        plans = try await stores.planStore.plans(in: range)
        // Always refreshed (not just when never loaded): recompute needs `workouts` to resolve
        // `plan.workoutID`, and the workout `plan` references might not be in the cached array yet.
        workouts = try await stores.workoutStore.workouts()
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Upserts `newCycles` into ``CycleStore``, reloads cycles from the store, and recomputes.
    ///
    /// If `load(in:asOf:)` hasn't been called yet, this falls back to a range covering the union
    /// of `newCycles`' date ranges (and adopts it as the loaded range), for the same reason as the
    /// `PlannedActivity` overload of `add` above.
    public func add(_ newCycles: [TrainingCycle], asOf today: Date = .now) async throws {
        try await stores.cycleStore.upsert(newCycles)
        let range = loadedRange ?? Self.union(of: newCycles.map(\.dateRange), fallback: today)
        cycles = try await stores.cycleStore.cycles(in: range)
        loadedRange = range
        await recompute(asOf: today)
    }

    /// Rebuilds ``metrics`` from the current activities/plans/workouts.
    ///
    /// `today` is injected, never read from `Date()` internally, for the same determinism reason
    /// as ``DailyLoadSeries``. The actual series/metrics computation runs off the main actor.
    public func recompute(asOf today: Date = .now) async {
        metrics = await Self.buildMetrics(
            activities: activities,
            plans: plans,
            workouts: workouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            parameters: parameters,
            today: today
        )
    }

    /// The smallest range covering every range in `ranges`, or `fallback...fallback` if `ranges`
    /// is empty.
    private static func union(of ranges: [ClosedRange<Date>], fallback: Date) -> ClosedRange<Date> {
        guard let first = ranges.first else { return fallback...fallback }
        return ranges.dropFirst().reduce(first) { partial, range in
            min(partial.lowerBound, range.lowerBound)...max(partial.upperBound, range.upperBound)
        }
    }

    /// Pure computation extracted so it runs off the main actor: calling a `nonisolated async`
    /// function from `@MainActor` code dispatches it onto the cooperative thread pool rather than
    /// running inline on the main actor's executor.
    private nonisolated static func buildMetrics(
        activities: [Activity],
        plans: [PlannedActivity],
        workouts: [StructuredWorkout],
        estimator: any PlannedLoadEstimator,
        calculators: [any LoadCalculator],
        athlete: AthleteProfile,
        parameters: LoadModelParameters,
        today: Date
    ) async -> [FitnessMetrics] {
        let days = DailyLoadSeries().days(
            activities: activities,
            plans: plans,
            workouts: workouts,
            estimator: estimator,
            calculators: calculators,
            athlete: athlete,
            today: today
        )
        return FitnessMetricsCalculator().metrics(for: days, parameters: parameters, seed: nil)
    }
}

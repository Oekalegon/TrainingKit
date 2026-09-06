import Foundation
import TrainingCore

/// Where every mutating ``TrainingTool`` writes. Snapshotted from the committed ``StoreSet`` up
/// front, then mutated in isolation by the model's tool calls; nothing here reaches the real
/// stores until ``commit(to:)``, which the app calls after the user reviews ``diff()`` —
/// `commit_sandbox` is deliberately not a tool the model itself can call.
///
/// A non-LLM UI can use this too, for "try this change and see the curve" without any model
/// involved.
public actor PlanSandbox {
    /// The sandbox's working set of planned activities — starts as a snapshot of the committed
    /// `PlanStore` and diverges as mutating tools call ``setPlans(_:)``.
    public var plans: [PlannedActivity]
    /// The sandbox's working set of library workouts — starts as a snapshot of the committed
    /// `WorkoutLibraryStore` and diverges as mutating tools call ``setWorkouts(_:)``.
    public var workouts: [StructuredWorkout]
    /// The sandbox's working set of cycles — starts as a snapshot of the committed `CycleStore`
    /// and diverges as mutating tools call ``setCycles(_:)``.
    public var cycles: [TrainingCycle]

    private let baselinePlans: [PlannedActivity]
    private let baselineWorkouts: [StructuredWorkout]
    private let baselineCycles: [TrainingCycle]

    private let activities: [Activity]
    private let athlete: AthleteProfile
    private let races: [Race]

    /// Snapshots `stores` into a new sandbox.
    ///
    /// - Parameters:
    ///   - stores: The committed stores to snapshot. Completed activities are read once and
    ///     never mutated by the sandbox — only `plans`/`workouts`/`cycles` are part of the
    ///     working set a tool can change.
    ///   - range: The window to snapshot activities/plans/cycles over. Defaults to roughly a
    ///     year back (enough for a full macrocycle of CTL history to seed `simulate`'s warm-up)
    ///     through six months ahead — wide enough for most planning horizons without pulling an
    ///     athlete's entire multi-year history out of the store on every sandbox construction.
    ///     Pass a wider range explicitly if a tool genuinely needs it (e.g. season-long stats).
    ///   - races: Races to evaluate race-day TSB against. `TrainingCore` has no `RaceStore` yet
    ///     (races are laid out through `CycleLayoutBuilder` inputs, not persisted per MVP 1), so
    ///     callers that have races in hand pass them here; defaults to none.
    /// - Throws: ``PlanSandboxError/missingAthleteProfile`` if `stores.athleteStore` has no
    ///   profile saved yet.
    public init(
        snapshotOf stores: StoreSet,
        range: ClosedRange<Date> = PlanSandbox.defaultSnapshotRange(),
        races: [Race] = []
    ) async throws {
        guard let athlete = try await stores.athleteStore.athleteProfile() else {
            throw PlanSandboxError.missingAthleteProfile
        }

        async let plans = stores.planStore.plans(in: range)
        async let workouts = stores.workoutStore.workouts()
        async let cycles = stores.cycleStore.cycles(in: range)
        async let activities = stores.activityStore.activities(in: range)

        let (fetchedPlans, fetchedWorkouts, fetchedCycles, fetchedActivities) =
            try await (plans, workouts, cycles, activities)

        self.plans = fetchedPlans
        self.baselinePlans = fetchedPlans
        self.workouts = fetchedWorkouts
        self.baselineWorkouts = fetchedWorkouts
        self.cycles = fetchedCycles
        self.baselineCycles = fetchedCycles
        self.activities = fetchedActivities
        self.athlete = athlete
        self.races = races
    }

    /// Roughly one year back through six months ahead of `now`, the default `init(snapshotOf:)`
    /// snapshot window.
    public static func defaultSnapshotRange(now: Date = Date()) -> ClosedRange<Date> {
        let secondsPerDay: TimeInterval = 86400
        return now.addingTimeInterval(-365 * secondsPerDay)...now.addingTimeInterval(180 * secondsPerDay)
    }

    // MARK: Mutations (what tools like `add_planned_activity`/`create_workout` call)

    /// Replaces the sandbox's working set of plans, e.g. after `add_planned_activity` or
    /// `move_planned_activity` computes the new array.
    public func setPlans(_ plans: [PlannedActivity]) {
        self.plans = plans
    }

    /// Replaces the sandbox's working set of library workouts, e.g. after `create_workout`.
    public func setWorkouts(_ workouts: [StructuredWorkout]) {
        self.workouts = workouts
    }

    /// Replaces the sandbox's working set of cycles, e.g. after `layout_cycles`.
    public func setCycles(_ cycles: [TrainingCycle]) {
        self.cycles = cycles
    }

    // MARK: Simulation, diff, commit, reset

    /// Recomputes the fitness series and evaluation over the sandbox's current working set —
    /// the model's what-if loop.
    ///
    /// - Parameters:
    ///   - engine: Builds the projected `[FitnessMetrics]` from `activities`/`plans`/`workouts`.
    ///   - evaluator: Checks the projected series against guardrails.
    ///   - today: The boundary between actual and projected days; injected so a replayed
    ///     conversation in tests simulates against a fixed date rather than `Date()`.
    ///   - guardrails: Forwarded to `evaluator`; defaults to `PlanGuardrails`'s defaults.
    public func simulate(
        engine: some SeriesEngine,
        evaluator: PlanEvaluator,
        today: Date,
        guardrails: PlanGuardrails = PlanGuardrails()
    ) -> SimulationResult {
        let metrics = engine.metrics(
            activities: activities,
            plans: plans,
            workouts: workouts,
            athlete: athlete,
            today: today
        )
        let evaluation = evaluator.evaluate(metrics, races: races, cycles: cycles, guardrails: guardrails)
        return SimulationResult(metrics: metrics, evaluation: evaluation)
    }

    /// A human-readable committed → sandbox summary, for the confirmation UI.
    public func diff() -> SandboxDiff {
        SandboxDiff(
            baselinePlans: baselinePlans, plans: plans,
            baselineWorkouts: baselineWorkouts, workouts: workouts,
            baselineCycles: baselineCycles, cycles: cycles
        )
    }

    /// Writes the sandbox's current working set to `stores`, replacing whatever plans/workouts/
    /// cycles were removed since the snapshot and upserting everything added or changed.
    public func commit(to stores: StoreSet) async throws {
        let diff = diff()

        if !plans.isEmpty { try await stores.planStore.upsert(plans) }
        for removed in diff.plans.removed {
            try await stores.planStore.deletePlan(id: removed.id)
        }

        if !workouts.isEmpty { try await stores.workoutStore.upsert(workouts) }
        for removed in diff.workouts.removed {
            try await stores.workoutStore.deleteWorkout(id: removed.id)
        }

        if !cycles.isEmpty { try await stores.cycleStore.upsert(cycles) }
        for removed in diff.cycles.removed {
            try await stores.cycleStore.deleteCycle(id: removed.id)
        }
    }

    /// Discards every mutation, restoring the working set to the snapshot taken at `init`.
    public func reset() {
        plans = baselinePlans
        workouts = baselineWorkouts
        cycles = baselineCycles
    }
}

public enum PlanSandboxError: Error, Sendable, Equatable {
    case missingAthleteProfile
}

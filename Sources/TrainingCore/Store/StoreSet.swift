/// Bundles the five Core store protocols so callers (``TrainingModel`` here, the MVP 2 LLM tool
/// layer later) can pass one value instead of five separate store parameters.
public struct StoreSet: Sendable {
    /// Storage for completed activities.
    public var activityStore: any ActivityStore
    /// Storage for planned activities.
    public var planStore: any PlanStore
    /// Storage for the workout library.
    public var workoutStore: any WorkoutLibraryStore
    /// Storage for training cycles.
    public var cycleStore: any CycleStore
    /// Storage for the athlete profile.
    public var athleteStore: any AthleteStore
    /// Storage for the persisted CTL/ATL/TSB/monotony/strain cache. `nil` disables caching
    /// entirely — ``TrainingModel`` recomputes the full daily series from scratch on every
    /// `recompute(asOf:)`, exactly as it did before this store existed.
    public var fitnessMetricsCacheStore: (any FitnessMetricsCacheStore)?

    /// Creates a store set.
    ///
    /// - Parameters:
    ///   - activityStore: Storage for completed activities.
    ///   - planStore: Storage for planned activities.
    ///   - workoutStore: Storage for the workout library.
    ///   - cycleStore: Storage for training cycles.
    ///   - athleteStore: Storage for the athlete profile.
    ///   - fitnessMetricsCacheStore: Storage for the persisted fitness-metrics cache; defaults to
    ///     `nil` (caching disabled), so every existing caller is unaffected.
    public init(
        activityStore: any ActivityStore,
        planStore: any PlanStore,
        workoutStore: any WorkoutLibraryStore,
        cycleStore: any CycleStore,
        athleteStore: any AthleteStore,
        fitnessMetricsCacheStore: (any FitnessMetricsCacheStore)? = nil
    ) {
        self.activityStore = activityStore
        self.planStore = planStore
        self.workoutStore = workoutStore
        self.cycleStore = cycleStore
        self.athleteStore = athleteStore
        self.fitnessMetricsCacheStore = fitnessMetricsCacheStore
    }
}

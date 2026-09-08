import Foundation

/// An in-memory implementation of all five Core store protocols, for tests and previews.
///
/// A single actor conforming to all five protocols at once is why the per-store mutation methods
/// above are named distinctly (`deletePlan`/`deleteWorkout`/`deleteCycle` rather than a shared
/// `delete(id:)`) — Swift can't satisfy identically-shaped requirements from different protocols
/// with different implementations on one conforming type.
public actor InMemoryStore: ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore,
    FitnessMetricsCacheStore {
    private var activitiesByID: [UUID: Activity] = [:]
    private var plansByID: [UUID: PlannedActivity] = [:]
    private var workoutsByID: [UUID: StructuredWorkout] = [:]
    private var cyclesByID: [UUID: TrainingCycle] = [:]
    private var profile: AthleteProfile?
    private var anchor: ImportAnchor?
    private var cachedMetricsByDay: [Date: FitnessMetrics] = [:]
    private var cacheDirtyWatermark: Date?

    /// Creates an empty in-memory store.
    public init() {}

    // MARK: ActivityStore

    /// See ``ActivityStore/activities(in:)``.
    public func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        activitiesByID.values.filter { range.contains($0.start) }
    }

    /// See ``ActivityStore/upsert(_:)``. Builds a `source` → `id` index once up front (kept in
    /// sync as each activity is applied, so two incoming activities that share a `source` within
    /// the same batch also dedupe against each other, not just against what was already stored)
    /// rather than a linear scan per activity.
    public func upsert(_ activities: [Activity]) async throws {
        var idBySource: [ActivitySource: UUID] = [:]
        for (id, existing) in activitiesByID where existing.source != .manual {
            idBySource[existing.source] = id
        }

        for activity in activities {
            if activity.source != .manual, let staleID = idBySource[activity.source], staleID != activity.id {
                activitiesByID.removeValue(forKey: staleID)
            }
            activitiesByID[activity.id] = activity
            if activity.source != .manual {
                idBySource[activity.source] = activity.id
            }
        }
    }

    /// See ``ActivityStore/activity(source:)``.
    public func activity(source: ActivitySource) async throws -> Activity? {
        activitiesByID.values.first { $0.source == source }
    }

    /// See ``ActivityStore/activity(id:)``.
    public func activity(id: UUID) async throws -> Activity? {
        activitiesByID[id]
    }

    /// See ``ActivityStore/deleteActivity(source:)``.
    public func deleteActivity(source: ActivitySource) async throws {
        guard let id = activitiesByID.values.first(where: { $0.source == source })?.id else { return }
        activitiesByID.removeValue(forKey: id)
    }

    // MARK: PlanStore

    /// See ``PlanStore/plans(in:)``.
    public func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
        plansByID.values.filter { range.contains($0.date) }
    }

    /// See ``PlanStore/upsert(_:)``.
    public func upsert(_ plans: [PlannedActivity]) async throws {
        for plan in plans {
            plansByID[plan.id] = plan
        }
    }

    /// See ``PlanStore/plan(id:)``.
    public func plan(id: UUID) async throws -> PlannedActivity? {
        plansByID[id]
    }

    /// See ``PlanStore/deletePlan(id:)``.
    public func deletePlan(id: UUID) async throws {
        plansByID.removeValue(forKey: id)
    }

    // MARK: WorkoutLibraryStore

    /// See ``WorkoutLibraryStore/workouts()``.
    public func workouts() async throws -> [StructuredWorkout] {
        Array(workoutsByID.values)
    }

    /// See ``WorkoutLibraryStore/workout(id:)``.
    public func workout(id: UUID) async throws -> StructuredWorkout? {
        workoutsByID[id]
    }

    /// See ``WorkoutLibraryStore/upsert(_:)``.
    public func upsert(_ workouts: [StructuredWorkout]) async throws {
        for workout in workouts {
            workoutsByID[workout.id] = workout
        }
    }

    /// See ``WorkoutLibraryStore/deleteWorkout(id:)``.
    public func deleteWorkout(id: UUID) async throws {
        workoutsByID.removeValue(forKey: id)
    }

    // MARK: CycleStore

    /// See ``CycleStore/cycles(in:)``.
    public func cycles(in range: ClosedRange<Date>) async throws -> [TrainingCycle] {
        cyclesByID.values.filter { $0.dateRange.overlaps(range) }
    }

    /// See ``CycleStore/cycle(id:)``.
    public func cycle(id: UUID) async throws -> TrainingCycle? {
        cyclesByID[id]
    }

    /// See ``CycleStore/upsert(_:)``. Nesting/overlap validation is shared with every other
    /// `CycleStore` conformer via ``CycleNestingValidator``.
    public func upsert(_ cycles: [TrainingCycle]) async throws {
        try CycleNestingValidator.validate(cycles, existing: cyclesByID)
        for cycle in cycles {
            cyclesByID[cycle.id] = cycle
        }
    }

    /// See ``CycleStore/deleteCycle(id:)``.
    public func deleteCycle(id: UUID) async throws {
        guard !cyclesByID.values.contains(where: { $0.parentID == id }) else {
            throw CycleStoreError.hasChildren(id)
        }
        cyclesByID.removeValue(forKey: id)
    }

    // MARK: AthleteStore

    /// See ``AthleteStore/athleteProfile()``.
    public func athleteProfile() async throws -> AthleteProfile? {
        profile
    }

    /// See ``AthleteStore/save(_:)``.
    public func save(_ profile: AthleteProfile) async throws {
        self.profile = profile
    }

    /// See ``AthleteStore/importAnchor()``.
    public func importAnchor() async throws -> ImportAnchor? {
        anchor
    }

    /// See ``AthleteStore/saveImportAnchor(_:)``.
    public func saveImportAnchor(_ anchor: ImportAnchor?) async throws {
        self.anchor = anchor
    }

    // MARK: FitnessMetricsCacheStore

    /// See ``FitnessMetricsCacheStore/cachedMetrics(in:)``.
    public func cachedMetrics(in range: ClosedRange<Date>) async throws -> [FitnessMetrics] {
        cachedMetricsByDay.values.filter { range.contains($0.day) }
    }

    /// See ``FitnessMetricsCacheStore/cachedMetrics(immediatelyBefore:)``.
    public func cachedMetrics(immediatelyBefore date: Date) async throws -> FitnessMetrics? {
        cachedMetricsByDay.values.filter { $0.day < date }.max { $0.day < $1.day }
    }

    /// See ``FitnessMetricsCacheStore/recentLoads(before:count:)``.
    public func recentLoads(before date: Date, count: Int) async throws -> [Double] {
        cachedMetricsByDay.values
            .filter { $0.day < date }
            .sorted { $0.day < $1.day }
            .suffix(count)
            .map(\.load)
    }

    /// See ``FitnessMetricsCacheStore/latestCachedDay()``.
    public func latestCachedDay() async throws -> Date? {
        cachedMetricsByDay.keys.max()
    }

    /// See ``FitnessMetricsCacheStore/earliestCachedDay()``.
    public func earliestCachedDay() async throws -> Date? {
        cachedMetricsByDay.keys.min()
    }

    /// See ``FitnessMetricsCacheStore/upsert(_:)``.
    public func upsert(_ metrics: [FitnessMetrics]) async throws {
        for metric in metrics {
            cachedMetricsByDay[metric.day] = metric
        }
    }

    /// See ``FitnessMetricsCacheStore/deleteCachedMetrics(from:)``.
    public func deleteCachedMetrics(from date: Date) async throws {
        cachedMetricsByDay = cachedMetricsByDay.filter { $0.key < date }
    }

    /// See ``FitnessMetricsCacheStore/dirtyWatermark()``.
    public func dirtyWatermark() async throws -> Date? {
        cacheDirtyWatermark
    }

    /// See ``FitnessMetricsCacheStore/markDirty(from:)``.
    public func markDirty(from date: Date) async throws {
        cacheDirtyWatermark = min(cacheDirtyWatermark ?? .distantFuture, date)
    }

    /// See ``FitnessMetricsCacheStore/clearDirtyWatermark()``.
    public func clearDirtyWatermark() async throws {
        cacheDirtyWatermark = nil
    }
}

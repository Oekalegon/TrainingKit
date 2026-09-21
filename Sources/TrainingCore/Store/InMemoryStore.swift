import Foundation

/// An in-memory implementation of all six Core store protocols, for tests and previews.
///
/// A single actor conforming to all six protocols at once is why the per-store mutation methods
/// above are named distinctly (`deletePlan`/`deleteWorkout`/`deleteCycle` rather than a shared
/// `delete(id:)`) — Swift can't satisfy identically-shaped requirements from different protocols
/// with different implementations on one conforming type.
public actor InMemoryStore: ActivityStore, PlanStore, WorkoutLibraryStore, WorkoutTemplateStore, CycleStore,
    AthleteStore, FitnessMetricsCacheStore {
    private var activitiesByID: [UUID: Activity] = [:]
    private var deletedSources: Set<ActivitySource> = []
    /// Joined activity id → its component ids. See ``ActivityStore/saveJoin(_:components:replacing:)``.
    var componentIDsByJoinID: [UUID: [UUID]] = [:]
    private var plansByID: [UUID: PlannedActivity] = [:]
    private var workoutsByID: [UUID: StructuredWorkout] = [:]
    private var templatesByID: [UUID: WorkoutTemplate] = [:]
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
        let hidden = Set(componentIDsByJoinID.values.joined())
        var result = activitiesByID.values.filter { range.contains($0.start) && !hidden.contains($0.id) }
        let shown = Set(result.map(\.id))
        for (joinID, componentIDs) in componentIDsByJoinID where !shown.contains(joinID) {
            let anyComponentInRange = componentIDs.contains { id in activitiesByID[id].map { range.contains($0.start) } ?? false }
            if anyComponentInRange, let joined = activitiesByID[joinID] { result.append(joined) }
        }
        return result
    }

    /// See ``ActivityStore/saveJoin(_:components:replacing:)``.
    public func saveJoin(_ merged: Activity, components: [UUID], replacing replacedJoinIDs: [UUID]) async throws {
        let ignored = Set(replacedJoinIDs).union([merged.id])
        let taken = Set(componentIDsByJoinID.filter { !ignored.contains($0.key) }.values.joined())
        if let duplicate = components.first(where: taken.contains) {
            throw ActivityJoinError.componentAlreadyJoined(duplicate)
        }
        for id in replacedJoinIDs {
            componentIDsByJoinID.removeValue(forKey: id)
            activitiesByID.removeValue(forKey: id)
        }
        activitiesByID[merged.id] = merged
        componentIDsByJoinID[merged.id] = components
    }

    /// See ``ActivityStore/joinedActivity(containing:)``.
    public func joinedActivity(containing componentID: UUID) async throws -> Activity? {
        componentIDsByJoinID.first { $0.value.contains(componentID) }.flatMap { activitiesByID[$0.key] }
    }

    /// See ``ActivityStore/components(ofJoinedActivity:)``.
    public func components(ofJoinedActivity id: UUID) async throws -> [Activity] {
        (componentIDsByJoinID[id] ?? []).compactMap { activitiesByID[$0] }.sorted { $0.start < $1.start }
    }

    /// See ``ActivityStore/unjoinActivity(id:)``.
    public func unjoinActivity(id: UUID) async throws {
        guard componentIDsByJoinID.removeValue(forKey: id) != nil else { return }
        activitiesByID.removeValue(forKey: id)
    }

    /// See ``ActivityStore/upsert(_:)``. Builds a `source` → `id` index once up front (kept in
    /// sync as each activity is applied, so two incoming activities that share a `source` within
    /// the same batch also dedupe against each other, not just against what was already stored)
    /// rather than a linear scan per activity.
    public func upsert(_ activities: [Activity]) async throws {
        var idBySource: [ActivitySource: UUID] = [:]
        for (id, existing) in activitiesByID where existing.source.hasNaturalKey {
            idBySource[existing.source] = id
        }

        for activity in activities {
            if activity.source.hasNaturalKey, let staleID = idBySource[activity.source], staleID != activity.id {
                activitiesByID.removeValue(forKey: staleID)
            }
            activitiesByID[activity.id] = activity
            if activity.source.hasNaturalKey {
                idBySource[activity.source] = activity.id
                deletedSources.remove(activity.source)
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
        // A piece removed at its origin leaves its joined activity describing a session that no
        // longer exists as recorded, so the join dissolves and the surviving pieces reappear.
        for (joinID, componentIDs) in componentIDsByJoinID where componentIDs.contains(id) {
            componentIDsByJoinID.removeValue(forKey: joinID)
            activitiesByID.removeValue(forKey: joinID)
        }
    }

    /// See ``ActivityStore/deleteActivity(id:)``.
    public func deleteActivity(id: UUID) async throws {
        if let componentIDs = componentIDsByJoinID.removeValue(forKey: id) {
            let stillJoined = Set(componentIDsByJoinID.values.joined())
            for componentID in componentIDs where !stillJoined.contains(componentID) {
                try await deleteActivity(id: componentID)
            }
        }
        if let activity = activitiesByID[id], activity.source.hasNaturalKey {
            deletedSources.insert(activity.source)
        }
        activitiesByID.removeValue(forKey: id)
    }

    /// See ``ActivityStore/tombstonedSources(among:)``.
    public func tombstonedSources(among sources: [ActivitySource]) async throws -> Set<ActivitySource> {
        Set(sources).intersection(deletedSources)
    }

    /// See ``ActivityStore/deduplicateActivities()``. See ``ActivityDeduplication/ordered(_:)``
    /// for which duplicate is kept.
    @discardableResult
    public func deduplicateActivities() async throws -> [Activity] {
        var bySource: [ActivitySource: [Activity]] = [:]
        for activity in activitiesByID.values where activity.source.hasNaturalKey {
            bySource[activity.source, default: []].append(activity)
        }

        var removed: [Activity] = []
        for group in bySource.values where group.count > 1 {
            let sorted = ActivityDeduplication.ordered(group)
            for duplicate in sorted.dropFirst() {
                activitiesByID.removeValue(forKey: duplicate.id)
                removed.append(duplicate)
            }
        }
        return removed.sorted { $0.start < $1.start }
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

    // MARK: WorkoutTemplateStore

    /// See ``WorkoutTemplateStore/templates()``.
    public func templates() async throws -> [WorkoutTemplate] {
        Array(templatesByID.values)
    }

    /// See ``WorkoutTemplateStore/template(id:)``.
    public func template(id: UUID) async throws -> WorkoutTemplate? {
        templatesByID[id]
    }

    /// See ``WorkoutTemplateStore/upsert(_:)``.
    public func upsert(_ templates: [WorkoutTemplate]) async throws {
        for template in templates {
            templatesByID[template.id] = template
        }
    }

    /// See ``WorkoutTemplateStore/deleteTemplate(id:)``.
    public func deleteTemplate(id: UUID) async throws {
        templatesByID.removeValue(forKey: id)
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

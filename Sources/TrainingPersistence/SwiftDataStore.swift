import TrainingCore
import Foundation
import SwiftData

/// SwiftData-backed implementation of all five Core store protocols, sharing one `ModelContainer`.
///
/// A single actor conforming to all five protocols at once, for the same reason as `InMemoryStore`:
/// Swift can't satisfy identically-shaped requirements from different protocols with different
/// implementations on one conforming type, hence the distinct `deletePlan`/`deleteWorkout`/
/// `deleteCycle` names rather than one shared `delete(id:)`.
///
/// `@ModelActor` synthesizes the `modelContainer`/`modelExecutor` and the `init(modelContainer:)`
/// this type is created with; `modelContext` (used throughout below) comes from the `ModelActor`
/// protocol it conforms to.
///
/// Every query but `activities(in:)` fetches every row of the relevant model type and
/// filters/decodes in Swift, exactly mirroring `InMemoryStore`'s in-memory filtering —
/// deliberately simple rather than pushing range/dedupe predicates into SwiftData, since a
/// `#Predicate` can't inspect fields inside an opaque `Data` payload anyway (see
/// ``ActivityRecord``). Fine at the data volumes those tables produce; worth revisiting with
/// indexed date fields if profiling ever shows otherwise. `activities(in:)` is the one query that
/// already needed this: see its doc comment below.
@ModelActor
public actor SwiftDataStore: ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore,
    FitnessMetricsCacheStore {
    // MARK: ActivityStore

    /// See `ActivityStore/activities(in:)`.
    ///
    /// Unlike the other `in:`-range queries below, this pushes the range into the fetch predicate
    /// against `ActivityRecord.start` rather than fetching every row and filtering in Swift — the
    /// activity table is large enough (years of imported history) that decoding every `payload` on
    /// every call is a measurable cost the other, smaller tables don't have.
    public func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        let descriptor = FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.start >= lowerBound && $0.start <= upperBound }
        )
        return try modelContext.fetch(descriptor).map { try $0.toActivity() }
    }

    /// See `ActivityStore/upsert(_:)`.
    ///
    /// Looks up every existing record with one fetch of the whole table, rather than one fetch
    /// per incoming activity — for an import of hundreds or thousands of activities (a full
    /// HealthKit history import, say), N individual fetches each pay their own query overhead,
    /// while one fetch plus an in-memory dictionary lookup does not. Every newly inserted record
    /// is added to that same dictionary as it's created, so two incoming activities that share an
    /// id neither of which is in the store yet still resolve to a single row (update, not a second
    /// insert) — matching what a live per-item fetch would have found, and what `ActivityRecord`'s
    /// own doc comment promises about uniqueness-by-id.
    ///
    /// Also indexes existing records by `sourceKey` (skipping `.manual`, which has no natural key)
    /// so an incoming activity whose source already belongs to a *different* stored id deletes that
    /// stale record instead of leaving it behind as a duplicate — see ``ActivityStore/upsert(_:)``'s
    /// doc comment for why this defense-in-depth exists alongside the primary id match.
    public func upsert(_ activities: [Activity]) async throws {
        var recordsByID: [UUID: ActivityRecord] = [:]
        var recordsBySourceKey: [String: ActivityRecord] = [:]
        let manualKey = ActivitySource.manual.persistenceKey
        for record in try modelContext.fetch(FetchDescriptor<ActivityRecord>()) {
            recordsByID[record.id] = record
            if record.sourceKey != manualKey {
                recordsBySourceKey[record.sourceKey] = record
            }
        }

        for activity in activities {
            let sourceKey = activity.source.persistenceKey
            if sourceKey != manualKey, let stale = recordsBySourceKey[sourceKey], stale.id != activity.id {
                modelContext.delete(stale)
                recordsByID.removeValue(forKey: stale.id)
            }

            let record: ActivityRecord
            if let existing = recordsByID[activity.id] {
                try existing.update(from: activity)
                record = existing
            } else {
                record = try ActivityRecord(activity: activity)
                modelContext.insert(record)
            }
            recordsByID[activity.id] = record
            if sourceKey != manualKey {
                recordsBySourceKey[sourceKey] = record
            }
        }
        try modelContext.save()
    }

    /// See `ActivityStore/activity(source:)`.
    public func activity(source: ActivitySource) async throws -> Activity? {
        try fetchActivityRecord(source: source)?.toActivity()
    }

    /// See `ActivityStore/activity(id:)`.
    public func activity(id: UUID) async throws -> Activity? {
        try fetchActivityRecord(id: id)?.toActivity()
    }

    /// See `ActivityStore/deleteActivity(source:)`.
    public func deleteActivity(source: ActivitySource) async throws {
        guard let record = try fetchActivityRecord(source: source) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    /// Deletes every activity in this store, returning how many were removed.
    ///
    /// Not part of `ActivityStore` — no Core protocol needs a bulk-clear operation, and no shipped
    /// app should either. Exists only for `TestApps/HealthKitHarness`/`PersistenceHarness` to reset
    /// between manual test runs (via `@testable import TrainingPersistence`), and for tests here —
    /// deliberately `internal`, not `public`, so it can't become a real button in a real app by
    /// accident. Deletes are tracked individually by SwiftData's CloudKit mirroring exactly like
    /// `deleteActivity(source:)`, so they propagate to every other device syncing this store.
    @discardableResult
    func deleteAllActivities() async throws -> Int {
        let records = try modelContext.fetch(FetchDescriptor<ActivityRecord>())
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
        return records.count
    }

    /// See `ActivityStore/deduplicateActivities()`. See `ActivityDeduplication.ordered(_:)` for
    /// which duplicate is kept — deciding that means decoding every candidate's `payload` (the
    /// heart-rate samples it compares on aren't stored as their own queryable column), but a
    /// duplicate group is expected to be tiny (a handful of rows at most), so this is cheap.
    @discardableResult
    public func deduplicateActivities() async throws -> [Activity] {
        let manualKey = ActivitySource.manual.persistenceKey
        var bySourceKey: [String: [ActivityRecord]] = [:]
        for record in try modelContext.fetch(FetchDescriptor<ActivityRecord>()) where record.sourceKey != manualKey {
            bySourceKey[record.sourceKey, default: []].append(record)
        }

        var removed: [Activity] = []
        for group in bySourceKey.values where group.count > 1 {
            let decoded = try group.map { (record: $0, activity: try $0.toActivity()) }
            let keptID = ActivityDeduplication.ordered(decoded.map(\.activity)).first?.id
            for pair in decoded where pair.activity.id != keptID {
                removed.append(pair.activity)
                modelContext.delete(pair.record)
            }
        }
        if !removed.isEmpty {
            try modelContext.save()
        }
        return removed.sorted { $0.start < $1.start }
    }

    private func fetchActivityRecord(id: UUID) throws -> ActivityRecord? {
        let descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func fetchActivityRecord(source: ActivitySource) throws -> ActivityRecord? {
        let key = source.persistenceKey
        let descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.sourceKey == key })
        return try modelContext.fetch(descriptor).first
    }

    // MARK: PlanStore

    /// See `PlanStore/plans(in:)`.
    public func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] {
        try modelContext.fetch(FetchDescriptor<PlannedActivityRecord>())
            .map { try $0.toPlan() }
            .filter { range.contains($0.date) }
    }

    /// See `PlanStore/upsert(_:)`. See ``upsert(_:)`` (`ActivityStore`'s) for why this looks up
    /// every existing record with one fetch rather than one fetch per incoming plan, and why newly
    /// inserted records are added back into that lookup as they're created.
    public func upsert(_ plans: [PlannedActivity]) async throws {
        var recordsByID: [UUID: PlannedActivityRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<PlannedActivityRecord>()) {
            recordsByID[record.id] = record
        }

        for plan in plans {
            if let existing = recordsByID[plan.id] {
                try existing.update(from: plan)
            } else {
                let record = try PlannedActivityRecord(plan: plan)
                modelContext.insert(record)
                recordsByID[plan.id] = record
            }
        }
        try modelContext.save()
    }

    /// See `PlanStore/plan(id:)`.
    public func plan(id: UUID) async throws -> PlannedActivity? {
        try fetchPlanRecord(id: id)?.toPlan()
    }

    /// See `PlanStore/deletePlan(id:)`.
    public func deletePlan(id: UUID) async throws {
        guard let record = try fetchPlanRecord(id: id) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func fetchPlanRecord(id: UUID) throws -> PlannedActivityRecord? {
        let descriptor = FetchDescriptor<PlannedActivityRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    // MARK: WorkoutLibraryStore

    /// See `WorkoutLibraryStore/workouts()`.
    public func workouts() async throws -> [StructuredWorkout] {
        try modelContext.fetch(FetchDescriptor<StructuredWorkoutRecord>()).map { try $0.toWorkout() }
    }

    /// See `WorkoutLibraryStore/workout(id:)`.
    public func workout(id: UUID) async throws -> StructuredWorkout? {
        try fetchWorkoutRecord(id: id)?.toWorkout()
    }

    /// See `WorkoutLibraryStore/upsert(_:)`. See ``upsert(_:)`` (`ActivityStore`'s) for why this
    /// looks up every existing record with one fetch rather than one fetch per incoming workout,
    /// and why newly inserted records are added back into that lookup as they're created.
    public func upsert(_ workouts: [StructuredWorkout]) async throws {
        var recordsByID: [UUID: StructuredWorkoutRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<StructuredWorkoutRecord>()) {
            recordsByID[record.id] = record
        }

        for workout in workouts {
            if let existing = recordsByID[workout.id] {
                try existing.update(from: workout)
            } else {
                let record = try StructuredWorkoutRecord(workout: workout)
                modelContext.insert(record)
                recordsByID[workout.id] = record
            }
        }
        try modelContext.save()
    }

    /// See `WorkoutLibraryStore/deleteWorkout(id:)`.
    public func deleteWorkout(id: UUID) async throws {
        guard let record = try fetchWorkoutRecord(id: id) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func fetchWorkoutRecord(id: UUID) throws -> StructuredWorkoutRecord? {
        let descriptor = FetchDescriptor<StructuredWorkoutRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    // MARK: CycleStore

    /// See `CycleStore/cycles(in:)`.
    public func cycles(in range: ClosedRange<Date>) async throws -> [TrainingCycle] {
        try modelContext.fetch(FetchDescriptor<TrainingCycleRecord>())
            .map { try $0.toCycle() }
            .filter { $0.dateRange.overlaps(range) }
    }

    /// See `CycleStore/cycle(id:)`.
    public func cycle(id: UUID) async throws -> TrainingCycle? {
        try fetchCycleRecord(id: id)?.toCycle()
    }

    /// See `CycleStore/upsert(_:)`. Nesting/overlap validation is shared with every other
    /// `CycleStore` conformer via `CycleNestingValidator`. Reuses the one fetch this needs anyway
    /// (to decode every existing cycle for validation) as the update lookup too, rather than
    /// fetching again per cycle — see ``upsert(_:)`` (`ActivityStore`'s) for why that matters, and
    /// why newly inserted records are added back into that lookup as they're created.
    public func upsert(_ cycles: [TrainingCycle]) async throws {
        var existingRecordsByID: [UUID: TrainingCycleRecord] = [:]
        var existingByID: [UUID: TrainingCycle] = [:]
        for record in try modelContext.fetch(FetchDescriptor<TrainingCycleRecord>()) {
            existingRecordsByID[record.id] = record
            existingByID[record.id] = try record.toCycle()
        }
        try CycleNestingValidator.validate(cycles, existing: existingByID)

        for cycle in cycles {
            if let existing = existingRecordsByID[cycle.id] {
                try existing.update(from: cycle)
            } else {
                let record = try TrainingCycleRecord(cycle: cycle)
                modelContext.insert(record)
                existingRecordsByID[cycle.id] = record
            }
        }
        try modelContext.save()
    }

    /// See `CycleStore/deleteCycle(id:)`.
    public func deleteCycle(id: UUID) async throws {
        let hasChildren = try modelContext.fetch(FetchDescriptor<TrainingCycleRecord>())
            .contains { try $0.toCycle().parentID == id }
        guard !hasChildren else {
            throw CycleStoreError.hasChildren(id)
        }
        guard let record = try fetchCycleRecord(id: id) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func fetchCycleRecord(id: UUID) throws -> TrainingCycleRecord? {
        let descriptor = FetchDescriptor<TrainingCycleRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    // MARK: AthleteStore

    /// See `AthleteStore/athleteProfile()`.
    public func athleteProfile() async throws -> AthleteProfile? {
        try singletonRecordIfExists()?.toProfile()
    }

    /// See `AthleteStore/save(_:)`.
    public func save(_ profile: AthleteProfile) async throws {
        let record = try singletonRecord()
        try record.update(from: profile)
        try modelContext.save()
    }

    /// See `AthleteStore/importAnchor()`.
    public func importAnchor() async throws -> ImportAnchor? {
        guard let data = try singletonRecordIfExists()?.importAnchorData else { return nil }
        return ImportAnchor(data: data)
    }

    /// See `AthleteStore/saveImportAnchor(_:)`.
    public func saveImportAnchor(_ anchor: ImportAnchor?) async throws {
        let record = try singletonRecord()
        record.importAnchorData = anchor?.data
        try modelContext.save()
    }

    private func singletonRecordIfExists() throws -> AthleteProfileRecord? {
        try modelContext.fetch(FetchDescriptor<AthleteProfileRecord>()).first
    }

    /// Fetches the one ``AthleteProfileRecord``, creating (but not yet saving) it if this is the
    /// first write of either the profile or the import anchor.
    private func singletonRecord() throws -> AthleteProfileRecord {
        if let existing = try singletonRecordIfExists() {
            return existing
        }
        let record = AthleteProfileRecord()
        modelContext.insert(record)
        return record
    }

    // MARK: FitnessMetricsCacheStore
    //
    // Unlike most other `in:`-range queries in this file, these push their date bound into the
    // fetch predicate/sort rather than fetching every row and filtering in Swift — `day` (unlike
    // most other records' date fields) is a plain queryable column, not something buried inside an
    // opaque `Data` payload, so there's no reason not to, and the cache is exactly the table most
    // likely to accumulate years of one-row-per-day history.

    /// See `FitnessMetricsCacheStore/cachedMetrics(in:)`.
    public func cachedMetrics(in range: ClosedRange<Date>) async throws -> [FitnessMetrics] {
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        let descriptor = FetchDescriptor<FitnessMetricsRecord>(
            predicate: #Predicate { $0.day >= lowerBound && $0.day <= upperBound }
        )
        return try modelContext.fetch(descriptor).map { try $0.toMetrics() }
    }

    /// See `FitnessMetricsCacheStore/cachedMetrics(immediatelyBefore:)`.
    public func cachedMetrics(immediatelyBefore date: Date) async throws -> FitnessMetrics? {
        var descriptor = FetchDescriptor<FitnessMetricsRecord>(predicate: #Predicate { $0.day < date })
        descriptor.sortBy = [SortDescriptor(\.day, order: .reverse)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { try $0.toMetrics() }
    }

    /// See `FitnessMetricsCacheStore/recentLoads(before:count:)`. Reads the queryable `load`
    /// column directly rather than `toMetrics()`, so this never decodes a payload just for one
    /// `Double`.
    public func recentLoads(before date: Date, count: Int) async throws -> [Double] {
        var descriptor = FetchDescriptor<FitnessMetricsRecord>(predicate: #Predicate { $0.day < date })
        descriptor.sortBy = [SortDescriptor(\.day, order: .reverse)]
        descriptor.fetchLimit = count
        // Fetched newest-first (to get the *trailing* `count` via `fetchLimit`) — reversed back to
        // the oldest-first order the protocol documents.
        return try modelContext.fetch(descriptor).map(\.load).reversed()
    }

    /// See `FitnessMetricsCacheStore/latestCachedDay()`.
    public func latestCachedDay() async throws -> Date? {
        var descriptor = FetchDescriptor<FitnessMetricsRecord>()
        descriptor.sortBy = [SortDescriptor(\.day, order: .reverse)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.day
    }

    /// See `FitnessMetricsCacheStore/earliestCachedDay()`.
    public func earliestCachedDay() async throws -> Date? {
        var descriptor = FetchDescriptor<FitnessMetricsRecord>()
        descriptor.sortBy = [SortDescriptor(\.day)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.day
    }

    /// See `FitnessMetricsCacheStore/upsert(_:)`. See ``upsert(_:)`` (`ActivityStore`'s) for why
    /// this looks up every existing record with one fetch rather than one fetch per incoming day,
    /// and why newly inserted records are added back into that lookup as they're created.
    public func upsert(_ metrics: [FitnessMetrics]) async throws {
        var recordsByDay: [Date: FitnessMetricsRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<FitnessMetricsRecord>()) {
            recordsByDay[record.day] = record
        }

        for metric in metrics {
            if let existing = recordsByDay[metric.day] {
                try existing.update(from: metric)
            } else {
                let record = try FitnessMetricsRecord(metrics: metric)
                modelContext.insert(record)
                recordsByDay[metric.day] = record
            }
        }
        try modelContext.save()
    }

    /// See `FitnessMetricsCacheStore/deleteCachedMetrics(from:)`.
    ///
    /// Not currently called by ``TrainingModel``'s own cache-fill algorithm — every previously
    /// cached day within a recompute's range gets overwritten via ``upsert(_:)`` rather than
    /// needing an explicit delete-then-reinsert, since a recompute always extends at least through
    /// whatever was last cached. Kept as public store API surface (tested at this layer) for a
    /// future explicit "clear the cache" action or a full-resync path that wants to start clean.
    public func deleteCachedMetrics(from date: Date) async throws {
        let descriptor = FetchDescriptor<FitnessMetricsRecord>(predicate: #Predicate { $0.day >= date })
        let records = try modelContext.fetch(descriptor)
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// See `FitnessMetricsCacheStore/dirtyWatermark()`.
    public func dirtyWatermark() async throws -> Date? {
        try cacheStateSingletonRecordIfExists()?.dirtyWatermark
    }

    /// See `FitnessMetricsCacheStore/markDirty(from:)`.
    public func markDirty(from date: Date) async throws {
        let record = try cacheStateSingletonRecord()
        record.dirtyWatermark = min(record.dirtyWatermark ?? .distantFuture, date)
        try modelContext.save()
    }

    /// See `FitnessMetricsCacheStore/clearDirtyWatermark()`.
    public func clearDirtyWatermark() async throws {
        guard let record = try cacheStateSingletonRecordIfExists() else { return }
        record.dirtyWatermark = nil
        try modelContext.save()
    }

    private func cacheStateSingletonRecordIfExists() throws -> FitnessMetricsCacheStateRecord? {
        try modelContext.fetch(FetchDescriptor<FitnessMetricsCacheStateRecord>()).first
    }

    /// Fetches the one ``FitnessMetricsCacheStateRecord``, creating (but not yet saving) it if this
    /// is the first time the watermark is written.
    private func cacheStateSingletonRecord() throws -> FitnessMetricsCacheStateRecord {
        if let existing = try cacheStateSingletonRecordIfExists() {
            return existing
        }
        let record = FitnessMetricsCacheStateRecord()
        modelContext.insert(record)
        return record
    }
}

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
public actor SwiftDataStore: ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore {
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
    /// while one fetch plus an in-memory dictionary lookup does not.
    public func upsert(_ activities: [Activity]) async throws {
        var recordsByID: [UUID: ActivityRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<ActivityRecord>()) {
            recordsByID[record.id] = record
        }

        for activity in activities {
            if let existing = recordsByID[activity.id] {
                try existing.update(from: activity)
            } else {
                modelContext.insert(try ActivityRecord(activity: activity))
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
    /// Not part of `ActivityStore` — no Core protocol needs a bulk-clear operation — but useful
    /// for cleaning up after a since-fixed import bug duplicated records, or for a test harness
    /// that wants to reset between runs. Deletes are tracked individually by SwiftData's CloudKit
    /// mirroring exactly like `deleteActivity(source:)`, so they propagate to every other device
    /// syncing this store.
    @discardableResult
    public func deleteAllActivities() async throws -> Int {
        let records = try modelContext.fetch(FetchDescriptor<ActivityRecord>())
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
        return records.count
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
    /// every existing record with one fetch rather than one fetch per incoming plan.
    public func upsert(_ plans: [PlannedActivity]) async throws {
        var recordsByID: [UUID: PlannedActivityRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<PlannedActivityRecord>()) {
            recordsByID[record.id] = record
        }

        for plan in plans {
            if let existing = recordsByID[plan.id] {
                try existing.update(from: plan)
            } else {
                modelContext.insert(try PlannedActivityRecord(plan: plan))
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
    /// looks up every existing record with one fetch rather than one fetch per incoming workout.
    public func upsert(_ workouts: [StructuredWorkout]) async throws {
        var recordsByID: [UUID: StructuredWorkoutRecord] = [:]
        for record in try modelContext.fetch(FetchDescriptor<StructuredWorkoutRecord>()) {
            recordsByID[record.id] = record
        }

        for workout in workouts {
            if let existing = recordsByID[workout.id] {
                try existing.update(from: workout)
            } else {
                modelContext.insert(try StructuredWorkoutRecord(workout: workout))
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
    /// fetching again per cycle — see ``upsert(_:)`` (`ActivityStore`'s) for why that matters.
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
                modelContext.insert(try TrainingCycleRecord(cycle: cycle))
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
}

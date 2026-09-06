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
/// Every query fetches every row of the relevant model type and filters/decodes in Swift, exactly
/// mirroring `InMemoryStore`'s in-memory filtering — deliberately simple rather than pushing
/// range/dedupe predicates into SwiftData, since a `#Predicate` can't inspect fields inside an
/// opaque `Data` payload anyway (see ``ActivityRecord``). Fine at the data volumes a single
/// athlete's training log produces; worth revisiting with indexed date fields if profiling ever
/// shows otherwise.
@ModelActor
public actor SwiftDataStore: ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore {
    // MARK: ActivityStore

    /// See `ActivityStore/activities(in:)`.
    public func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        try modelContext.fetch(FetchDescriptor<ActivityRecord>())
            .map { try $0.toActivity() }
            .filter { range.contains($0.start) }
    }

    /// See `ActivityStore/upsert(_:)`.
    public func upsert(_ activities: [Activity]) async throws {
        for activity in activities {
            if let existing = try fetchActivityRecord(id: activity.id) {
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

    /// See `PlanStore/upsert(_:)`.
    public func upsert(_ plans: [PlannedActivity]) async throws {
        for plan in plans {
            if let existing = try fetchPlanRecord(id: plan.id) {
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

    /// See `WorkoutLibraryStore/upsert(_:)`.
    public func upsert(_ workouts: [StructuredWorkout]) async throws {
        for workout in workouts {
            if let existing = try fetchWorkoutRecord(id: workout.id) {
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
    /// `CycleStore` conformer via `CycleNestingValidator`.
    public func upsert(_ cycles: [TrainingCycle]) async throws {
        var existingByID: [UUID: TrainingCycle] = [:]
        for record in try modelContext.fetch(FetchDescriptor<TrainingCycleRecord>()) {
            existingByID[record.id] = try record.toCycle()
        }
        try CycleNestingValidator.validate(cycles, existing: existingByID)

        for cycle in cycles {
            if let existing = try fetchCycleRecord(id: cycle.id) {
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

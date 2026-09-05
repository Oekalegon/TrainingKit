import Foundation

/// An in-memory implementation of all five Core store protocols, for tests and previews.
///
/// A single actor conforming to all five protocols at once is why the per-store mutation methods
/// above are named distinctly (`deletePlan`/`deleteWorkout`/`deleteCycle` rather than a shared
/// `delete(id:)`) — Swift can't satisfy identically-shaped requirements from different protocols
/// with different implementations on one conforming type.
public actor InMemoryStore: ActivityStore, PlanStore, WorkoutLibraryStore, CycleStore, AthleteStore {
    private var activitiesByID: [UUID: Activity] = [:]
    private var plansByID: [UUID: PlannedActivity] = [:]
    private var workoutsByID: [UUID: StructuredWorkout] = [:]
    private var cyclesByID: [UUID: TrainingCycle] = [:]
    private var profile: AthleteProfile?

    /// Creates an empty in-memory store.
    public init() {}

    // MARK: ActivityStore

    /// See ``ActivityStore/activities(in:)``.
    public func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        activitiesByID.values.filter { range.contains($0.start) }
    }

    /// See ``ActivityStore/upsert(_:)``.
    public func upsert(_ activities: [Activity]) async throws {
        for activity in activities {
            activitiesByID[activity.id] = activity
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

    /// See ``CycleStore/upsert(_:)``. Validates each cycle in `cycles` against a working copy
    /// seeded from the currently-stored cycles, updated incrementally as the batch is processed —
    /// so a parent and its children can be upserted together in one call.
    public func upsert(_ cycles: [TrainingCycle]) async throws {
        var workingSet = cyclesByID
        for cycle in cycles {
            if let parentID = cycle.parentID {
                guard let parent = workingSet[parentID] else {
                    throw CycleStoreError.parentNotFound(parentID)
                }
                guard parent.dateRange.lowerBound <= cycle.dateRange.lowerBound,
                      cycle.dateRange.upperBound <= parent.dateRange.upperBound
                else {
                    throw CycleStoreError.childOutsideParentRange(child: cycle.id, parent: parentID)
                }
            }

            let siblings = workingSet.values.filter { $0.parentID == cycle.parentID && $0.id != cycle.id }
            for sibling in siblings where sibling.dateRange.overlaps(cycle.dateRange) {
                throw CycleStoreError.overlappingSiblings(cycle.id, sibling.id)
            }

            workingSet[cycle.id] = cycle
        }
        cyclesByID = workingSet
    }

    /// See ``CycleStore/deleteCycle(id:)``.
    public func deleteCycle(id: UUID) async throws {
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
}

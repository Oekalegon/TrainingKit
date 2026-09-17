import TrainingCore

/// A human-readable summary of how a ``PlanSandbox``'s working set diverges from what it was
/// snapshotted from, for a confirmation UI to show before the user commits.
public struct SandboxDiff: Sendable, Equatable {
    /// Added/removed/modified entries of one entity kind, keyed by identity (not equality) —
    /// an entry with the same `id` in both the baseline and the working set but different field
    /// values is `modified`, not one `removed` and one `added`.
    public struct Change<Value: Identifiable & Sendable & Equatable>: Sendable, Equatable where Value.ID: Sendable {
        public let added: [Value]
        public let removed: [Value]
        public let modified: [Value]

        public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }

        init(baseline: [Value], current: [Value]) {
            let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

            added = current.filter { baselineByID[$0.id] == nil }
            removed = baseline.filter { currentByID[$0.id] == nil }
            modified = current.filter { entry in
                guard let baselineEntry = baselineByID[entry.id] else { return false }
                return baselineEntry != entry
            }
        }
    }

    public let plans: Change<PlannedActivity>
    public let workouts: Change<StructuredWorkout>
    public let cycles: Change<TrainingCycle>

    public var isEmpty: Bool { plans.isEmpty && workouts.isEmpty && cycles.isEmpty }

    init(
        baselinePlans: [PlannedActivity], plans: [PlannedActivity],
        baselineWorkouts: [StructuredWorkout], workouts: [StructuredWorkout],
        baselineCycles: [TrainingCycle], cycles: [TrainingCycle]
    ) {
        self.plans = Change(baseline: baselinePlans, current: plans)
        self.workouts = Change(baseline: baselineWorkouts, current: workouts)
        self.cycles = Change(baseline: baselineCycles, current: cycles)
    }
}

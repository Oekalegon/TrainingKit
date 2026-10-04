import TrainingCore
import Foundation
// See the note in WorkoutStep+WorkoutKit.swift: this disambiguates Core's `WorkoutStep` from
// WorkoutKit's identically-named one and from the shadowing `TrainingCore` enum.
import struct TrainingCore.WorkoutStep

#if canImport(WorkoutKit)
import HealthKit
import WorkoutKit

/// Bridges `StructuredWorkout` (Core) to Apple WorkoutKit's `CustomWorkout`/`WorkoutPlan`, and
/// schedules plans onto the Watch.
///
/// Mapping is mechanical: `WorkoutBlock` ↔ `IntervalBlock`, `WorkoutStep` ↔ WorkoutKit's
/// `WorkoutStep`, `StepGoal` ↔ `WorkoutGoal`, `IntensityTarget` ↔ `WorkoutAlert` (see
/// `WorkoutKitMapping+Goals` and `WorkoutKitMapping+Alerts`). The one non-mechanical piece is the
/// warmup/cooldown split: `CustomWorkout` has dedicated `warmup`/`cooldown` slots holding a single
/// step each, while `StructuredWorkout` only has `blocks`. A leading or trailing block counts as
/// warmup/cooldown only when it's exactly one step of that `StepKind` with `repetitions == 1`;
/// anything else (a multi-step warmup block, or a `.warmup`-kind step buried mid-workout) maps as
/// an ordinary interval block instead, and a `.warmup`/`.cooldown` step *inside* an interval block
/// falls back to `IntervalStep.Purpose.work` — that enum only distinguishes work from recovery.
///
/// Sync is one-directional: library → WorkoutKit. A scheduled entry's `WorkoutPlan` id is the
/// ``PlannedActivity``'s id (see ``workoutPlan(for:workout:)``), so each entry belongs to one plan
/// and can be found again without storing anything.
public struct WorkoutKitBridge: Sendable {
    private let support: WorkoutKitSupportChecking

    /// Creates a WorkoutKit bridge. `WorkoutScheduler` has no public initializer, so scheduling
    /// always goes through `.shared`, WorkoutKit's only instance, rather than a stored dependency
    /// this type could inject a fake for in tests.
    public init() {
        self.support = .live
    }

    /// Internal seam for tests: substitutes a fake ``WorkoutKitSupportChecking`` so
    /// `unsupportedActivity`/`unsupportedGoalForActivity`/`unsupportedAlertForActivity` can be
    /// exercised deterministically, without depending on WorkoutKit's undocumented support tables.
    init(support: WorkoutKitSupportChecking) {
        self.support = support
    }

    /// Maps a library workout onto a `CustomWorkout`, validating every step's goal and alert
    /// against `workout.sport` along the way.
    ///
    /// - Parameter workout: The library workout to map.
    /// - Returns: A `CustomWorkout` WorkoutKit is guaranteed to accept for `workout.sport`.
    /// - Throws: ``WorkoutKitMappingError/unsupportedActivity(_:)`` if WorkoutKit doesn't support
    ///   `workout.sport` at all; ``WorkoutKitMappingError/unsupportedGoalForActivity(_:_:)`` or
    ///   ``WorkoutKitMappingError/unsupportedAlertForActivity(_:)`` if a specific step's goal or
    ///   alert isn't supported for that sport (per `CustomWorkout.supportsGoal`/`supportsAlert`) —
    ///   better to fail here than to hand the Watch app a `CustomWorkout` it'll reject or silently
    ///   strip alerts from.
    public func customWorkout(from workout: StructuredWorkout) throws(WorkoutKitMappingError) -> CustomWorkout {
        let activity = workout.sport.workoutKitActivityType
        guard support.supportsActivity(activity) else {
            throw .unsupportedActivity(activity)
        }

        var blocks = workout.blocks
        let warmupBlock = Self.extractEdgeStep(&blocks, kind: .warmup, fromStart: true)
        let cooldownBlock = Self.extractEdgeStep(&blocks, kind: .cooldown, fromStart: false)

        var warmupStep: WorkoutKit.WorkoutStep?
        if let warmupBlock {
            warmupStep = try workoutKitStep(for: warmupBlock.steps[0], activity: activity)
        }
        var cooldownStep: WorkoutKit.WorkoutStep?
        if let cooldownBlock {
            cooldownStep = try workoutKitStep(for: cooldownBlock.steps[0], activity: activity)
        }

        var intervalBlocks: [IntervalBlock] = []
        intervalBlocks.reserveCapacity(blocks.count)
        for block in blocks {
            var steps: [IntervalStep] = []
            steps.reserveCapacity(block.steps.count)
            for step in block.steps {
                let purpose: IntervalStep.Purpose = step.kind == .recovery ? .recovery : .work
                steps.append(IntervalStep(purpose, step: try workoutKitStep(for: step, activity: activity)))
            }
            intervalBlocks.append(IntervalBlock(steps: steps, iterations: block.repetitions))
        }

        return CustomWorkout(
            activity: activity,
            displayName: workout.name,
            warmup: warmupStep,
            blocks: intervalBlocks,
            cooldown: cooldownStep
        )
    }

    /// Maps a `WorkoutPlan` back onto a `StructuredWorkout`, tagged with the plan's id as
    /// `workoutKitID`.
    ///
    /// - Parameter plan: The plan to recover a `StructuredWorkout` from.
    /// - Returns: The recovered `StructuredWorkout`, with `workoutKitID` set to `plan.id`.
    /// - Throws: ``WorkoutKitMappingError/unsupportedWorkoutKind(_:)`` if `plan.workout` isn't
    ///   `.custom` — a `.goal`/`.pacer`/`.swimBikeRun` plan wasn't built by this bridge and has no
    ///   `StructuredWorkout` shape to recover. Also throws if any step's goal has no `StepGoal`
    ///   equivalent (see `StepGoal.init(workoutGoal:)`).
    public func structuredWorkout(from plan: WorkoutPlan) throws(WorkoutKitMappingError) -> StructuredWorkout {
        guard case .custom(let customWorkout) = plan.workout else {
            throw .unsupportedWorkoutKind(plan.workout)
        }

        var blocks: [WorkoutBlock] = []
        if let warmup = customWorkout.warmup {
            blocks.append(WorkoutBlock(steps: [try WorkoutStep(kind: .warmup, workoutKitStep: warmup)], repetitions: 1))
        }
        for intervalBlock in customWorkout.blocks {
            var steps: [WorkoutStep] = []
            steps.reserveCapacity(intervalBlock.steps.count)
            for intervalStep in intervalBlock.steps {
                let kind: StepKind = intervalStep.purpose == .recovery ? .recovery : .work
                steps.append(try WorkoutStep(kind: kind, workoutKitStep: intervalStep.step))
            }
            blocks.append(WorkoutBlock(steps: steps, repetitions: intervalBlock.iterations))
        }
        if let cooldown = customWorkout.cooldown {
            blocks.append(WorkoutBlock(steps: [try WorkoutStep(kind: .cooldown, workoutKitStep: cooldown)], repetitions: 1))
        }

        return StructuredWorkout(
            name: customWorkout.displayName ?? "Untitled Workout",
            sport: Sport(workoutKitActivityType: customWorkout.activity),
            blocks: blocks,
            workoutKitID: plan.id
        )
    }

    /// Validates and maps `workout` to a `CustomWorkout`, then hands back `workout.workoutKitID` if
    /// it has one, otherwise a new id.
    ///
    /// This doesn't schedule anything, and scheduling doesn't use the id it returns: a scheduled
    /// entry takes its plan's id instead (see ``workoutPlan(for:workout:)``). It exists so a caller
    /// can validate a workout up front. `async` to leave room for a real library-sync API if
    /// WorkoutKit ever grows one — WorkoutKit today has no concept of a workout library separate
    /// from scheduled plans.
    ///
    /// - Parameter workout: The workout to validate and mint/reuse a WorkoutKit plan id for.
    /// - Returns: `workout.workoutKitID` if already set, otherwise a freshly minted `UUID`.
    /// - Throws: Whatever ``customWorkout(from:)`` throws for `workout`.
    public func sync(_ workout: StructuredWorkout) async throws(WorkoutKitMappingError) -> UUID {
        _ = try customWorkout(from: workout)
        return workout.workoutKitID ?? UUID()
    }

    /// Builds the `WorkoutPlan` that puts `workout` on the Watch for `plan`, with `plan.id` as its id.
    ///
    /// The id is the ``PlannedActivity``'s, not the library workout's, so each scheduled entry
    /// belongs to exactly one plan (MVP2-55). A workout planned on several days, or twice on one day,
    /// gets a distinct entry each time, and a completed entry, or a recorded `HKWorkout` started from
    /// one, names the plan it fulfilled. `plan.id` is stable, so nothing extra needs storing to find
    /// the entry again.
    ///
    /// - Parameters:
    ///   - plan: The plan being scheduled; supplies the id.
    ///   - workout: The library workout `plan` schedules.
    /// - Returns: A `WorkoutPlan` wrapping `workout`'s `CustomWorkout`, with id `plan.id`.
    /// - Throws: Whatever ``customWorkout(from:)`` throws for `workout`.
    public func workoutPlan(for plan: PlannedActivity, workout: StructuredWorkout) throws(WorkoutKitMappingError) -> WorkoutPlan {
        WorkoutPlan(.custom(try customWorkout(from: workout)), id: plan.id)
    }

    /// Puts `workout` on the Watch for `plan.date` via `WorkoutScheduler`, replacing whatever was
    /// scheduled for `plan` before.
    ///
    /// The entry's id is `plan.id` (see ``workoutPlan(for:workout:)``). Any existing entry with that
    /// id is removed first, whatever its date, so a moved plan leaves nothing on its old day and an
    /// edited workout replaces the stale version. An entry that's already identical, same workout
    /// on the same day, is left alone, which keeps its completion flag and makes calling this
    /// again a no-op.
    ///
    /// WorkoutKit only shows ±7 days on the Watch and caps how many entries an app holds
    /// (`WorkoutScheduler.maxAllowedScheduledWorkoutCount`), so the caller is expected to call this
    /// only for plans within that window — this method has no such gating itself.
    ///
    /// - Parameters:
    ///   - plan: Supplies the date to schedule for and the entry's id.
    ///   - workout: The library workout `plan` schedules.
    ///   - calendar: Used to turn `plan.date` into the `DateComponents` the scheduler takes;
    ///     defaults to `.current`. Pass the athlete's own calendar (built from
    ///     `AthleteProfile.timeZone`) if it differs from the device's, since `plan.date` is a
    ///     calendar day in the athlete's timezone, not necessarily the device's.
    /// - Throws: Whatever ``customWorkout(from:)`` throws for `workout`. Nothing is removed from
    ///   WorkoutKit when it throws.
    public func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar = .current) async throws(WorkoutKitMappingError) {
        let desired = try workoutPlan(for: plan, workout: workout)
        let day = calendar.dateComponents([.year, .month, .day], from: plan.date)
        var alreadyScheduled = false
        for entry in await WorkoutScheduler.shared.scheduledWorkouts where entry.plan.id == plan.id {
            if !alreadyScheduled, entry.plan == desired, Self.isSameDay(entry.date, day) {
                alreadyScheduled = true
                continue
            }
            await WorkoutScheduler.shared.remove(entry.plan, at: entry.date)
        }
        if !alreadyScheduled {
            await WorkoutScheduler.shared.schedule(desired, at: day)
        }
    }

    /// Removes `plan`'s entry from `WorkoutScheduler`, for when the plan is deleted, so it doesn't
    /// keep showing on the Watch.
    ///
    /// Matches entries on `plan.id` alone, whatever their date, and removes the plan WorkoutKit holds
    /// rather than rebuilding one: `remove(_:at:)` takes a plan, and a workout edited since it was
    /// scheduled would rebuild to a different one. Nothing is mapped, so this doesn't throw. A no-op
    /// when nothing was scheduled for `plan`.
    ///
    /// Moving a plan to another day doesn't need this: ``schedule(_:workout:calendar:)`` already
    /// removes the old day's entry.
    ///
    /// - Parameter plan: The plan whose entry to remove.
    public func unschedule(_ plan: PlannedActivity) async {
        for entry in await WorkoutScheduler.shared.scheduledWorkouts where entry.plan.id == plan.id {
            await WorkoutScheduler.shared.remove(entry.plan, at: entry.date)
        }
    }

    /// Whether two `DateComponents` name the same calendar day — compares year/month/day only, since
    /// a scheduled entry's components may also carry time-of-day fields the `schedule` call never set.
    static func isSameDay(_ lhs: DateComponents, _ rhs: DateComponents) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
    }

    /// Maps `step`'s goal and alert onto a WorkoutKit step, checking both are supported for
    /// `activity` before handing back a step WorkoutKit is guaranteed to accept.
    private func workoutKitStep(for step: WorkoutStep, activity: HKWorkoutActivityType) throws(WorkoutKitMappingError) -> WorkoutKit.WorkoutStep {
        let goal = WorkoutGoal(stepGoal: step.goal)
        guard support.supportsGoal(goal, activity) else {
            throw .unsupportedGoalForActivity(goal, activity)
        }
        let alert = step.target?.workoutAlert
        if let alert, !support.supportsAlert(alert, activity) {
            throw .unsupportedAlertForActivity(activity)
        }
        return WorkoutKit.WorkoutStep(goal: goal, alert: alert)
    }

    /// If `blocks`' first (or last, when `fromStart` is `false`) element is exactly one step of
    /// `kind` with `repetitions == 1`, removes and returns it — the shape a warmup/cooldown block
    /// must have to map onto `CustomWorkout`'s single-step `warmup`/`cooldown` slot.
    private static func extractEdgeStep(_ blocks: inout [WorkoutBlock], kind: StepKind, fromStart: Bool) -> WorkoutBlock? {
        guard let edge = fromStart ? blocks.first : blocks.last,
              edge.repetitions == 1, edge.steps.count == 1, edge.steps[0].kind == kind
        else {
            return nil
        }
        if fromStart {
            blocks.removeFirst()
        } else {
            blocks.removeLast()
        }
        return edge
    }
}
#endif

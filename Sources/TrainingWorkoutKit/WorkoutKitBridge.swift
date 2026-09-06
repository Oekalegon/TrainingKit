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
/// Sync is one-directional in MVP 1: library → WorkoutKit. `StructuredWorkout.workoutKitID`
/// records the link (reused across ``sync(_:)``/``schedule(_:workout:calendar:)`` calls) so re-syncing
/// updates the same `WorkoutPlan` rather than creating a new one.
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

    /// Validates and maps `workout` to a `CustomWorkout`, then hands back the id its `WorkoutPlan`
    /// should carry — `workout.workoutKitID` if it already has one (so a re-sync updates the same
    /// plan rather than creating a second one), otherwise a new one.
    ///
    /// This doesn't schedule anything by itself; it exists so a caller can validate and obtain a
    /// stable id to persist as `StructuredWorkout.workoutKitID` before the workout is ever
    /// scheduled. `async` for symmetry with ``schedule(_:workout:calendar:)`` and to leave room for a real
    /// library-sync API if WorkoutKit ever grows one — WorkoutKit today has no concept of a
    /// workout library separate from scheduled plans.
    ///
    /// - Parameter workout: The workout to validate and mint/reuse a WorkoutKit plan id for.
    /// - Returns: `workout.workoutKitID` if already set, otherwise a freshly minted `UUID`.
    /// - Throws: Whatever ``customWorkout(from:)`` throws for `workout`.
    public func sync(_ workout: StructuredWorkout) async throws(WorkoutKitMappingError) -> UUID {
        _ = try customWorkout(from: workout)
        return workout.workoutKitID ?? UUID()
    }

    /// Schedules `workout` for `plan.date` via `WorkoutScheduler`.
    ///
    /// WorkoutKit only shows ±7 days on the Watch (per the design), so the caller is expected to
    /// call this lazily for plans within that window rather than for a whole season up front —
    /// this method has no such gating itself.
    ///
    /// - Parameters:
    ///   - plan: Supplies the date to schedule for.
    ///   - workout: The library workout `plan` schedules.
    ///   - calendar: Used to turn `plan.date` into the `DateComponents` the scheduler takes;
    ///     defaults to `.current`. Pass the athlete's own calendar (built from
    ///     `AthleteProfile.timeZone`) if it differs from the device's, since `plan.date` is a
    ///     calendar day in the athlete's timezone, not necessarily the device's.
    public func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar = .current) async throws(WorkoutKitMappingError) {
        let customWorkout = try customWorkout(from: workout)
        let planID = workout.workoutKitID ?? UUID()
        let workoutPlan = WorkoutPlan(.custom(customWorkout), id: planID)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: plan.date)
        await WorkoutScheduler.shared.schedule(workoutPlan, at: dateComponents)
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

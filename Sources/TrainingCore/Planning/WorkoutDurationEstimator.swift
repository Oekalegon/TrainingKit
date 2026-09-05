import Foundation

/// Estimates how long a ``StructuredWorkout`` (or a single ``WorkoutStep`` within one) will take,
/// independent of intensity/load.
///
/// Shared by ``TRIMPPlanEstimator`` (which also needs each step's intensity to compute load) and
/// ``PlanReconciler`` (which only needs the total duration, to tie-break candidate matches) so the
/// two never silently disagree about how long an `.open` step or a `.distance` step at an
/// unspecified zone is assumed to take.
public struct WorkoutDurationEstimator: Sendable {
    /// Duration assumed for `.open` steps, which have no explicit time or distance.
    public var defaultOpenStepDuration: TimeInterval

    public init(defaultOpenStepDuration: TimeInterval = 600) {
        self.defaultOpenStepDuration = defaultOpenStepDuration
    }

    /// The estimated duration of a single step. A `.distance` step with no `.heartRateZone`
    /// target assumes zone 3, for lack of a better default.
    public func duration(for step: WorkoutStep, athlete: AthleteProfile) -> TimeInterval {
        switch step.goal {
        case .time(let interval):
            return interval
        case .distance(let meters):
            let zone: Int
            if case .heartRateZone(let value) = step.target {
                zone = value
            } else {
                zone = 3
            }
            return athlete.paceModel.duration(forMeters: meters, atZone: zone)
        case .open:
            return defaultOpenStepDuration
        }
    }

    /// The estimated total duration of a workout, respecting each block's `repetitions`.
    public func duration(for workout: StructuredWorkout, athlete: AthleteProfile) -> TimeInterval {
        var total: TimeInterval = 0
        for block in workout.blocks {
            var blockTotal: TimeInterval = 0
            for step in block.steps {
                blockTotal += duration(for: step, athlete: athlete)
            }
            total += blockTotal * Double(block.repetitions)
        }
        return total
    }
}

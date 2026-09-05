import TrainingCore
import Foundation

#if canImport(WorkoutKit)
import WorkoutKit

extension WorkoutGoal {
    /// Maps a `StepGoal` onto its WorkoutKit equivalent. Total — every `StepGoal` case has one.
    public init(stepGoal: StepGoal) {
        switch stepGoal {
        case .time(let seconds):
            self = .time(seconds, .seconds)
        case .distance(let meters):
            self = .distance(meters, .meters)
        case .open:
            self = .open
        }
    }
}

extension StepGoal {
    /// Maps a WorkoutKit `WorkoutGoal` onto its `StepGoal` equivalent.
    ///
    /// - Throws: ``WorkoutKitMappingError/unsupportedGoal(_:)`` for `.energy` and
    ///   `.poolSwimDistanceWithTime` — `StepGoal` only models time, distance, and open-ended
    ///   steps, so an energy- or pool-length-based goal has nowhere to go.
    public init(workoutGoal: WorkoutGoal) throws(WorkoutKitMappingError) {
        switch workoutGoal {
        case .open:
            self = .open
        case .time(let value, let unit):
            self = .time(Measurement(value: value, unit: unit).converted(to: .seconds).value)
        case .distance(let value, let unit):
            self = .distance(Measurement(value: value, unit: unit).converted(to: .meters).value)
        case .energy, .poolSwimDistanceWithTime:
            throw .unsupportedGoal(workoutGoal)
        @unknown default:
            throw .unsupportedGoal(workoutGoal)
        }
    }
}
#endif

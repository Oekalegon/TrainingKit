import TrainingCore

#if canImport(WorkoutKit)
import HealthKit

extension Sport {
    /// Maps an `HKWorkoutActivityType` to the closest `Sport` case.
    ///
    /// Only the types `TrainingCore` has a direct case for are mapped explicitly; every other
    /// activity type falls back to `.other`, labeled via `Sport.otherLabel(rawValue:)` — the same
    /// format `TrainingHealthKit`'s `Sport(healthKitActivityType:)` uses — so a round trip through
    /// either adapter recovers the same `HKWorkoutActivityType` via ``workoutKitActivityType``.
    public init(workoutKitActivityType type: HKWorkoutActivityType) {
        switch type {
        case .running:
            self = .running
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self = .strength
        case .walking:
            self = .walking
        case .rowing:
            self = .rowing
        default:
            self = .other(Sport.otherLabel(rawValue: type.rawValue))
        }
    }

    /// The `HKWorkoutActivityType` a `CustomWorkout` should be built with for this sport.
    ///
    /// `.other` recovers the exact original type when its label was produced by
    /// `Sport.otherLabel(rawValue:)` (as ``init(workoutKitActivityType:)`` and
    /// `TrainingHealthKit`'s equivalent both do); any other `.other` label — e.g. one typed in by
    /// hand — falls back to `.other` since there's nothing else to recover it from.
    public var workoutKitActivityType: HKWorkoutActivityType {
        switch self {
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .strength:
            return .traditionalStrengthTraining
        case .walking:
            return .walking
        case .rowing:
            return .rowing
        case .other:
            return otherRawValue.flatMap { HKWorkoutActivityType(rawValue: $0) } ?? .other
        }
    }
}
#endif

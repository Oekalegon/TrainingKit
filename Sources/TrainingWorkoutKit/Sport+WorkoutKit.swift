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
        case .coreTraining:
            self = .coreStrengthTraining
        case .walking:
            self = .walking
        case .rowing:
            self = .rowing
        case .hiking:
            self = .hiking
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
        case .coreStrengthTraining:
            return .coreTraining
        case .walking:
            return .walking
        case .rowing:
            return .rowing
        case .hiking:
            return .hiking
        case .other:
            return otherRawValue.flatMap { HKWorkoutActivityType(rawValue: $0) } ?? .other
        }
    }
}

extension Venue {
    /// The `HKWorkoutSessionLocationType` a `CustomWorkout` is built with for this venue.
    ///
    /// HealthKit has no separate indoor or outdoor activity type, but `CustomWorkout` carries the venue
    /// as its `location`, and with it set the Watch doesn't ask "Indoor or Outdoor?" when the workout
    /// starts. Only indoors versus outdoors survives: the surface is dropped.
    public var workoutKitLocation: HKWorkoutSessionLocationType {
        isIndoor ? .indoor : .outdoor
    }

    /// The venue a `CustomWorkout`'s `location` names, or `nil` for `.unknown`. Always without a
    /// surface, since WorkoutKit doesn't carry one.
    public init?(workoutKitLocation location: HKWorkoutSessionLocationType) {
        switch location {
        case .indoor: self = .indoor(nil)
        case .outdoor: self = .outdoor(nil)
        default: return nil
        }
    }
}
#endif

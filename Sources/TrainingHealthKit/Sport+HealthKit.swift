import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension Sport {
    /// Maps an `HKWorkoutActivityType` to the closest `Sport` case.
    ///
    /// Only the types `TrainingCore` has a direct case for are mapped explicitly; every other
    /// HealthKit activity type (there are dozens) falls back to `.other`, labeled with the type's
    /// raw value so the original HealthKit type isn't lost even though `Sport` can't represent it
    /// precisely.
    public init(healthKitActivityType type: HKWorkoutActivityType) {
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
            self = .other("HKWorkoutActivityType(rawValue: \(type.rawValue))")
        }
    }
}
#endif

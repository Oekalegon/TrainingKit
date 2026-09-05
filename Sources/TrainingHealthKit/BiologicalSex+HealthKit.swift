import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension BiologicalSex {
    /// Maps an `HKBiologicalSex` to `BiologicalSex`. `.notSet` and `.other` both map to
    /// `.unspecified` — `TrainingCore` only distinguishes male/female (for `TRIMPCoefficients`
    /// selection) and everything else.
    public init(healthKitBiologicalSex sex: HKBiologicalSex) {
        switch sex {
        case .male:
            self = .male
        case .female:
            self = .female
        default:
            self = .unspecified
        }
    }
}
#endif

import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension SpeedSample {
    /// The unit HealthKit speed quantities are read in: meters per second.
    static let speedUnit = HKUnit.meter().unitDivided(by: .second())
}
#endif

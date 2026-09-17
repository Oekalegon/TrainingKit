import TrainingCore

#if canImport(HealthKit)
import HealthKit

extension HeartRateSample {
    /// The unit HealthKit heart-rate quantities are read in: beats per minute.
    static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

    /// Creates a heart-rate sample from an `HKQuantitySample`.
    ///
    /// - Parameter quantitySample: A sample from `HKQuantityType(.heartRate)`; behavior is
    ///   undefined for a sample of any other quantity type.
    public init(healthKitQuantitySample quantitySample: HKQuantitySample) {
        self.init(time: quantitySample.startDate, bpm: quantitySample.quantity.doubleValue(for: Self.heartRateUnit))
    }
}
#endif

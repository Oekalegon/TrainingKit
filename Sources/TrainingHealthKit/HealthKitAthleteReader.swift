import TrainingCore

#if canImport(HealthKit)
import HealthKit

/// Reads resting heart rate, biological sex, and (via `TanakaHRMaxEstimator`) an estimated
/// maximum heart rate from HealthKit, to pre-fill an `AthleteProfile`.
///
/// Never reads HRmax directly — HealthKit doesn't report one, so this always estimates from date
/// of birth instead, leaving the user to override it, per the design's Tanaka-formula-with-override
/// approach.
public struct HealthKitAthleteReader: Sendable {
    private let healthStore: HKHealthStore
    private let hrMaxEstimator: TanakaHRMaxEstimator

    /// Creates a HealthKit athlete reader.
    ///
    /// - Parameters:
    ///   - healthStore: The health store to read from; the caller is responsible for requesting
    ///     authorization first (see ``HealthKitAuthorization``).
    ///   - hrMaxEstimator: Estimates HRmax from date of birth; defaults to `TanakaHRMaxEstimator`.
    public init(healthStore: HKHealthStore, hrMaxEstimator: TanakaHRMaxEstimator = TanakaHRMaxEstimator()) {
        self.healthStore = healthStore
        self.hrMaxEstimator = hrMaxEstimator
    }

    /// Reads everything available, treating each field independently — a denied or never-recorded
    /// data type reports `nil` for that field rather than failing the whole snapshot.
    ///
    /// - Parameter today: The date to estimate HRmax as of; injected rather than `Date()` for
    ///   determinism, matching the rest of `TrainingCore`.
    /// - Returns: Whatever could be read.
    public func snapshot(asOf today: Date) async throws -> HealthKitAthleteSnapshot {
        async let restingHeartRate = latestRestingHeartRateBPM()
        async let biologicalSex = readBiologicalSex()
        async let maxHeartRate = estimatedMaxHeartRateBPM(asOf: today)
        return try await HealthKitAthleteSnapshot(
            restingHeartRateBPM: restingHeartRate,
            biologicalSex: biologicalSex,
            estimatedMaxHeartRateBPM: maxHeartRate
        )
    }

    private func latestRestingHeartRateBPM() async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        return samples.first?.quantity.doubleValue(for: HeartRateSample.heartRateUnit)
    }

    private func readBiologicalSex() async throws -> BiologicalSex? {
        let descriptor = try healthStore.biologicalSex()
        guard descriptor.biologicalSex != .notSet else { return nil }
        return BiologicalSex(healthKitBiologicalSex: descriptor.biologicalSex)
    }

    private func estimatedMaxHeartRateBPM(asOf today: Date) async throws -> Double? {
        guard let dateOfBirth = try healthStore.dateOfBirthComponents().date else { return nil }
        return hrMaxEstimator.estimatedMaxHeartRateBPM(dateOfBirth: dateOfBirth, asOf: today)
    }
}
#endif

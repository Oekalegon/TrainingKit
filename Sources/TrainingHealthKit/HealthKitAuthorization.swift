#if canImport(HealthKit)
import HealthKit

/// Requests the read authorizations `TrainingHealthKit` needs.
///
/// No write scopes in MVP 1 — import and athlete pre-fill are both read-only.
public enum HealthKitAuthorization {
    /// The HealthKit types this package reads: workouts, heart rate (during a workout and at
    /// rest), date of birth, and biological sex.
    public static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
    }

    /// Requests authorization to read ``readTypes`` from `healthStore`.
    ///
    /// - Parameter healthStore: The health store to request authorization on.
    public static func requestAuthorization(for healthStore: HKHealthStore) async throws {
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }
}
#endif

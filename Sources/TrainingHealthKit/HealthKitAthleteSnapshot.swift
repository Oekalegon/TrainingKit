import Foundation
import TrainingCore

/// Everything ``HealthKitAthleteReader`` could pre-fill an `AthleteProfile` with, in one read.
///
/// Every field is optional independently — HealthKit authorization is granted per data type, and
/// the user may have denied one type while allowing others, or simply never recorded it (e.g. no
/// resting-heart-rate samples yet).
public struct HealthKitAthleteSnapshot: Sendable, Hashable {
    /// Resting heart rate, in beats per minute, smoothed via `RestingHeartRateSmoother` over the
    /// trailing 1–2 week window rather than a single latest sample.
    public let restingHeartRateBPM: Double?
    /// The athlete's biological sex, if HealthKit has one on record.
    public let biologicalSex: BiologicalSex?
    /// Maximum heart rate estimated from date of birth via `TanakaHRMaxEstimator` — HealthKit
    /// never reports HRmax directly.
    public let estimatedMaxHeartRateBPM: Double?

    /// Creates an athlete snapshot.
    ///
    /// - Parameters:
    ///   - restingHeartRateBPM: The smoothed resting heart rate, if any readings were found.
    ///   - biologicalSex: The athlete's biological sex, if known.
    ///   - estimatedMaxHeartRateBPM: Maximum heart rate estimated from date of birth, if known.
    public init(restingHeartRateBPM: Double?, biologicalSex: BiologicalSex?, estimatedMaxHeartRateBPM: Double?) {
        self.restingHeartRateBPM = restingHeartRateBPM
        self.biologicalSex = biologicalSex
        self.estimatedMaxHeartRateBPM = estimatedMaxHeartRateBPM
    }
}

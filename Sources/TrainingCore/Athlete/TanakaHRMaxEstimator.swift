import Foundation

/// Estimates maximum heart rate from age using the Tanaka formula, for athletes without a measured
/// HRmax.
///
/// HealthKit never reports HRmax directly (per `TrainingHealthKit`'s design), so `dateOfBirth` —
/// which HealthKit does report — is converted through this estimator instead; the user can always
/// override the result.
public struct TanakaHRMaxEstimator: Sendable {
    /// Creates a Tanaka HRmax estimator.
    public init() {}

    /// The Tanaka-formula estimate, `208 − 0.7 × age`, using a continuous age in years rather than
    /// a whole-number age — a smoother, marginally more accurate default that avoids needing a
    /// `Calendar`/timezone for a value that's just a starting point the user can override anyway.
    ///
    /// - Parameters:
    ///   - dateOfBirth: The athlete's date of birth.
    ///   - today: The date to compute age as of; injected rather than `Date()` for determinism.
    /// - Returns: The estimated maximum heart rate, in beats per minute.
    public func estimatedMaxHeartRateBPM(dateOfBirth: Date, asOf today: Date) -> Double {
        let secondsPerYear = 365.2425 * 86400
        let age = today.timeIntervalSince(dateOfBirth) / secondsPerYear
        return 208 - 0.7 * age
    }
}

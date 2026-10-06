import Foundation

/// Where a ``HeartRateZoneSettings/maxHeartRateBPM`` value came from.
///
/// Max heart rate drives the Karvonen and %-of-max zones and the heart-rate-reserve ratio TRIMP
/// is built on. A value estimated from age (``TanakaHRMaxEstimator``) is commonly off by around
/// 10 bpm for an individual, so a measured value should take precedence over the formula once one
/// exists. Recording the source lets a host app avoid overwriting a measured max with a fresh
/// formula estimate, and lets the athlete see how trustworthy the number is.
public enum MaxHeartRateSource: Sendable, Codable, Hashable {
    /// Estimated from age, e.g. by ``TanakaHRMaxEstimator``. The default for settings recorded
    /// before sources were tracked.
    case formula
    /// Reached during an ordinary workout: the highest heart rate the athlete held for a few
    /// seconds (see ``PeakHeartRateDetector``). A lower bound on the true maximum, which may be
    /// higher still.
    ///
    /// - Parameter activityID: The ``Activity`` the peak was measured in.
    case workout(activityID: UUID)
    /// Entered by the athlete (MVP2-132), e.g. from a field test. Taken as given: nothing replaces
    /// it automatically, and it isn't compared with the age formula or a workout's peak.
    case manual
}

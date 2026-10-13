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
    /// Measured by the max heart rate field test (``WorkoutPurpose/maxHRTest``, MVP2-154): the highest
    /// heart rate held for a few seconds in a test activity linked to its plan. Unlike
    /// ``workout(activityID:)`` it may be lower than the value it replaces, since a test is a
    /// deliberate attempt at the maximum.
    ///
    /// - Parameter activityID: The ``Activity`` the test was recorded in.
    case fieldTest(activityID: UUID)
    /// Measured in a laboratory (a graded exercise test) and entered by the athlete. The most reliable
    /// source: nothing else replaces it automatically, and a field test or a workout only does after
    /// the athlete confirms.
    case labTest
    /// Entered by the athlete (MVP2-132) without saying how it was found, e.g. a figure from a watch or
    /// a guess. Taken as given: an age formula never replaces it, but it ranks below a measurement.
    case manual

    /// How far this source can be trusted, higher being more reliable (see ``isReplaceable(by:)``):
    /// ``formula`` 0, ``manual`` 1, ``workout(activityID:)`` 2, ``fieldTest(activityID:)`` 3,
    /// ``labTest`` 4.
    ///
    /// A workout's held peak is a lower bound on the true maximum, a field test is a deliberate attempt
    /// at it, and a lab test measures it under control. A figure the athlete typed in without a source
    /// is above an estimate from age but below any measurement. Only the order matters, not the values.
    public var reliabilityRank: Int {
        switch self {
        case .formula: 0
        case .manual: 1
        case .workout: 2
        case .fieldTest: 3
        case .labTest: 4
        }
    }

    /// Whether a value from `other` may take this source's place without the athlete deciding: `other`
    /// is at least as reliable (``reliabilityRank``). A host app that merges in estimates should check
    /// `current.isReplaceable(by: .formula)` before overwriting, so an age formula never replaces a
    /// measured or entered maximum.
    ///
    /// This is a guard for automatic updates. It doesn't stop the athlete confirming a lower-ranked
    /// result: a workout whose held peak beats the maximum on record is proof that the record is too low,
    /// whatever its source (``AthleteProfile/raisingMaxHeartRate(to:from:source:)``).
    ///
    /// - Parameter other: The source of the value that would replace this one.
    public func isReplaceable(by other: MaxHeartRateSource) -> Bool {
        other.reliabilityRank >= reliabilityRank
    }
}

import Foundation

/// Where a ``HeartRateZoneSettings/maxHeartRateBPM`` value came from.
///
/// Max heart rate drives the Karvonen and %-of-max zones and the heart-rate-reserve ratio TRIMP
/// is built on. A value estimated from age (``TanakaHRMaxEstimator``) is commonly off by around
/// 10 bpm for an individual, so a measured value should take precedence over the formula once one
/// exists. Recording the source lets a host app avoid overwriting a measured max with a fresh
/// formula estimate, and lets the athlete see how trustworthy the number is.
///
/// The sources are ranked (``reliabilityRank(asOf:)``) and ``isReplaceable(by:asOf:)`` is the guard for
/// automatic updates. Only a ``labTest(measuredOn:)`` ages today: it drops a step below a field test
/// after ``labTestFreshness``. A field test or workout peak doesn't age yet, since max heart rate
/// changes slowly and a held peak stays a lower bound; LTHR does drift faster (see
/// ``LactateThresholdSource``).
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
    /// source while it is fresh (see ``labTestFreshness``): then nothing else replaces it automatically,
    /// and a field test or a workout only does after the athlete confirms. Once older, it ranks below a
    /// field test, since max heart rate falls with age and the athlete may have changed.
    ///
    /// - Parameter measuredOn: The day the test was done. Kept here, not taken from the settings'
    ///   effective date, because a later settings entry (a resting-heart-rate update) is a copy that
    ///   carries the source forward and would otherwise make an old test look new.
    case labTest(measuredOn: Date)
    /// Entered by the athlete (MVP2-132) without saying how it was found, e.g. a figure from a watch or
    /// a guess. Taken as given: an age formula never replaces it, but it ranks below a measurement.
    case manual

    /// How long a ``labTest(measuredOn:)`` keeps its top rank: two years. Beyond it the test ranks one
    /// step below a field test. Our own choice: max heart rate falls by roughly a beat a year, so a
    /// two-year-old lab figure is still a good reference but no longer beats a fresh attempt.
    public static let labTestFreshness: TimeInterval = 2 * 365 * 24 * 60 * 60

    /// How far this source can be trusted on `today`, higher being more reliable (see
    /// ``isReplaceable(by:asOf:)``): ``formula`` 0, ``manual`` 1, ``workout(activityID:)`` 2,
    /// ``fieldTest(activityID:)`` 3, a fresh ``labTest(measuredOn:)`` 4. A lab test older than
    /// ``labTestFreshness`` ranks 2, with a workout: still above a formula or a typed-in figure.
    ///
    /// A workout's held peak is a lower bound on the true maximum, a field test is a deliberate attempt
    /// at it, and a lab test measures it under control. A figure the athlete typed in without a source
    /// is above an estimate from age but below any measurement. Only the order matters, not the values.
    ///
    /// - Parameter today: The day to judge the age of a lab test on. A caller comparing with a new result
    ///   passes that result's date, so the answer doesn't depend on the clock.
    public func reliabilityRank(asOf today: Date) -> Int {
        switch self {
        case .formula: 0
        case .manual: 1
        case .workout: 2
        case .fieldTest: 3
        case .labTest(let measuredOn):
            today.timeIntervalSince(measuredOn) > Self.labTestFreshness ? 2 : 4
        }
    }

    /// Whether a value from `other`, measured on `today`, may take this source's place without the
    /// athlete deciding: `other` is at least as reliable. A host app that merges in estimates should
    /// check `current.isReplaceable(by: .formula, asOf: today)` before overwriting, so an age formula
    /// never replaces a measured or entered maximum.
    ///
    /// This is a guard for automatic updates. It doesn't stop the athlete confirming a lower-ranked
    /// result: a workout whose held peak beats the maximum on record is proof that the record is too low,
    /// whatever its source (``AthleteProfile/raisingMaxHeartRate(to:from:source:)``).
    ///
    /// - Parameters:
    ///   - other: The source of the value that would replace this one.
    ///   - today: The day of the new value, which is also when this source's age is judged.
    public func isReplaceable(by other: MaxHeartRateSource, asOf today: Date) -> Bool {
        other.reliabilityRank(asOf: today) >= reliabilityRank(asOf: today)
    }
}

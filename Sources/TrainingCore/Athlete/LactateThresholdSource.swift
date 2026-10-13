import Foundation

/// Where a ``HeartRateZoneSettings/lactateThresholdHeartRateBPM`` value came from (MVP2-154).
///
/// Like ``MaxHeartRateSource``, this lets a host app show how trustworthy the number is and avoid
/// replacing a measured value with an estimate.
public enum LactateThresholdSource: Sendable, Codable, Hashable {
    /// Entered by the athlete without saying how it was found, e.g. a watch's estimate. The default for
    /// settings recorded before sources were tracked, since the athlete was then the only source. Ranks
    /// below a measurement.
    case manual
    /// Measured in a laboratory (a lactate test) and entered by the athlete. The most reliable source
    /// while it is fresh (see ``labTestFreshness``), a ranking below a field test afterwards.
    ///
    /// - Parameter measuredOn: The day the test was done; see ``MaxHeartRateSource/labTest(measuredOn:)``
    ///   for why it is kept here.
    case labTest(measuredOn: Date)
    /// Measured by the 30-minute field test (``WorkoutPurpose/lthrTest``): the average heart rate over
    /// the last 20 minutes of the effort.
    ///
    /// - Parameter activityID: The ``Activity`` the test was recorded in.
    case fieldTest(activityID: UUID)

    /// How long a ``labTest(measuredOn:)`` keeps its top rank: 90 days. Our own choice: threshold heart
    /// rate follows fitness over weeks to months, so a lab figure a few months old is worth less than a
    /// field test done now.
    public static let labTestFreshness: TimeInterval = 90 * 24 * 60 * 60

    /// How far this source can be trusted on `today`, higher being more reliable (see
    /// ``isReplaceable(by:asOf:)``): ``manual`` 0, ``fieldTest(activityID:)`` 1, a fresh
    /// ``labTest(measuredOn:)`` 2. A lab test older than ``labTestFreshness`` ranks 0, with a typed-in
    /// figure. Only the order matters.
    ///
    /// - Parameter today: The day to judge the age of a lab test on.
    public func reliabilityRank(asOf today: Date) -> Int {
        switch self {
        case .manual: 0
        case .fieldTest: 1
        case .labTest(let measuredOn):
            today.timeIntervalSince(measuredOn) > Self.labTestFreshness ? 0 : 2
        }
    }

    /// Whether a value from `other`, measured on `today`, may take this source's place without the
    /// athlete deciding: `other` is at least as reliable. A guard for automatic updates, like
    /// ``MaxHeartRateSource/isReplaceable(by:asOf:)``.
    ///
    /// - Parameters:
    ///   - other: The source of the value that would replace this one.
    ///   - today: The day of the new value, which is also when this source's age is judged.
    public func isReplaceable(by other: LactateThresholdSource, asOf today: Date) -> Bool {
        other.reliabilityRank(asOf: today) >= reliabilityRank(asOf: today)
    }
}

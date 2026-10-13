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
    /// Measured in a laboratory (a lactate test) and entered by the athlete. The most reliable source.
    case labTest
    /// Measured by the 30-minute field test (``WorkoutPurpose/lthrTest``): the average heart rate over
    /// the last 20 minutes of the effort.
    ///
    /// - Parameter activityID: The ``Activity`` the test was recorded in.
    case fieldTest(activityID: UUID)

    /// How far this source can be trusted, higher being more reliable (see ``isReplaceable(by:)``):
    /// ``manual`` 0, ``fieldTest(activityID:)`` 1, ``labTest`` 2. Only the order matters.
    public var reliabilityRank: Int {
        switch self {
        case .manual: 0
        case .fieldTest: 1
        case .labTest: 2
        }
    }

    /// Whether a value from `other` may take this source's place without the athlete deciding: `other` is
    /// at least as reliable (``reliabilityRank``). A guard for automatic updates, like
    /// ``MaxHeartRateSource/isReplaceable(by:)``.
    ///
    /// - Parameter other: The source of the value that would replace this one.
    public func isReplaceable(by other: LactateThresholdSource) -> Bool {
        other.reliabilityRank >= reliabilityRank
    }
}

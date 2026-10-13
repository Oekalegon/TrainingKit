import Foundation

/// Where a ``HeartRateZoneSettings/lactateThresholdHeartRateBPM`` value came from (MVP2-154).
///
/// Like ``MaxHeartRateSource``, this lets a host app show how trustworthy the number is and avoid
/// replacing a measured value with an estimate.
public enum LactateThresholdSource: Sendable, Codable, Hashable {
    /// Entered by the athlete, e.g. from a lab test or a watch's estimate. The default for settings
    /// recorded before sources were tracked, since the athlete was then the only source.
    case manual
    /// Measured by the 30-minute field test (``WorkoutPurpose/lthrTest``): the average heart rate over
    /// the last 20 minutes of the effort.
    ///
    /// - Parameter activityID: The ``Activity`` the test was recorded in.
    case fieldTest(activityID: UUID)
}

import Foundation

/// The distance and duration a planned ``StructuredWorkout`` is expected to produce, from
/// ``StatisticsCalculator/projection(for:athlete:)``.
public struct WorkoutProjection: Sendable, Hashable {
    /// The expected distance in meters, or `nil` when it couldn't be derived — the athlete has no
    /// current heart-rate zone settings, so step intensities (and hence paces) are unknown.
    public let distanceMeters: Double?
    /// The expected duration in seconds.
    public let duration: TimeInterval
    /// How many earlier activities the paces were forecast from (see ``PaceHistory``); `0` when
    /// the projection rests on ``AthleteProfile/paceModel`` alone.
    public let matchedActivityCount: Int

    /// Creates a workout projection.
    ///
    /// - Parameters:
    ///   - distanceMeters: The expected distance, if it could be derived.
    ///   - duration: The expected duration in seconds.
    ///   - matchedActivityCount: How many earlier activities the paces were forecast from.
    public init(distanceMeters: Double?, duration: TimeInterval, matchedActivityCount: Int = 0) {
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.matchedActivityCount = matchedActivityCount
    }
}

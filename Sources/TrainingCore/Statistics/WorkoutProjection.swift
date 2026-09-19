import Foundation

/// The distance and duration a planned ``StructuredWorkout`` is expected to produce, from
/// ``StatisticsCalculator/projection(for:athlete:)``.
public struct WorkoutProjection: Sendable, Hashable {
    /// The expected distance in meters, or `nil` when it couldn't be derived — the athlete has no
    /// current heart-rate zone settings, so step intensities (and hence paces) are unknown.
    public let distanceMeters: Double?
    /// The expected duration in seconds.
    public let duration: TimeInterval

    /// Creates a workout projection.
    ///
    /// - Parameters:
    ///   - distanceMeters: The expected distance, if it could be derived.
    ///   - duration: The expected duration in seconds.
    public init(distanceMeters: Double?, duration: TimeInterval) {
        self.distanceMeters = distanceMeters
        self.duration = duration
    }
}

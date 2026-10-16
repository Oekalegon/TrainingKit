import Foundation

/// One planned session as the paradigm rules of ``PlanEvaluator`` see it.
///
/// The evaluator works on already-described sessions, not on workouts, so it stays a pure function;
/// ``PlannedIntensityClassifier/session(on:for:athlete:)`` builds one from a ``StructuredWorkout``.
public struct PlanSession: Sendable, Codable, Hashable {
    /// The calendar day of the session, day-granular in the same timezone as the metrics it is
    /// evaluated with.
    public let day: Date
    /// The planned duration in seconds; the weight of the session in a distribution.
    public let seconds: TimeInterval
    /// The session's intensity from its time in zones.
    public let intensity: IntensityCategory
    /// The session's fastest work, independent of `intensity`.
    public let speed: SpeedLevel

    /// Creates a planned session.
    ///
    /// - Parameters:
    ///   - day: The calendar day of the session.
    ///   - seconds: The planned duration in seconds.
    ///   - intensity: The session's intensity from its time in zones.
    ///   - speed: The session's fastest work.
    public init(day: Date, seconds: TimeInterval, intensity: IntensityCategory, speed: SpeedLevel) {
        self.day = day
        self.seconds = seconds
        self.intensity = intensity
        self.speed = speed
    }
}

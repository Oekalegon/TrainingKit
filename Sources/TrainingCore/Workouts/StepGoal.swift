import Foundation

/// What ends a ``WorkoutStep``: a fixed duration, a fixed distance, or an open-ended step left to
/// the athlete (e.g. "run until you feel ready").
public enum StepGoal: Sendable, Codable, Hashable {
    case time(TimeInterval)
    case distance(Double)
    case open
}

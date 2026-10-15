/// What a ``GoalTarget/volume(sport:measure:amount:per:)`` goal counts.
public enum GoalMeasure: Sendable, Codable, Hashable, CaseIterable {
    /// Distance covered, in meters.
    case distanceMeters
    /// Time spent training, in seconds.
    case durationSeconds
}

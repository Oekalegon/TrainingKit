import Foundation

/// What a ``Goal`` asks for.
///
/// Targets are checked by the athlete, not by TrainingKit: nothing here is evaluated against
/// activities yet.
public enum GoalTarget: Sendable, Codable, Hashable {
    /// Cover a distance in a time or faster, e.g. running 5 km in under 20 minutes.
    case time(sport: Sport, distanceMeters: Double, seconds: TimeInterval)
    /// Reach an amount over a recurring period, e.g. running 1500 km per year.
    ///
    /// - `sport`: the sport the amount counts, or `nil` for all sports together.
    case volume(sport: Sport?, measure: GoalMeasure, amount: Double, per: GoalPeriod)
    /// A goal in the athlete's own words, with no structured target; ``Goal/name`` and
    /// ``Goal/notes`` say what it is.
    case freeText
}

/// What a ``GoalTarget/volume(sport:measure:amount:per:)`` goal counts.
public enum GoalMeasure: Sendable, Codable, Hashable, CaseIterable {
    /// Distance covered, in meters.
    case distanceMeters
    /// Time spent training, in seconds.
    case durationSeconds
}

/// The recurring period a ``GoalTarget/volume(sport:measure:amount:per:)`` goal's amount is counted over.
///
/// A rolling period, not a date range: a goal has no dates (see ``Goal``).
public enum GoalPeriod: Sendable, Codable, Hashable, CaseIterable {
    case week
    case month
    case year
}

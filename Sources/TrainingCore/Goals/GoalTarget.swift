import Foundation

/// What a ``Goal`` asks for.
///
/// Targets are checked by the athlete, not by TrainingKit: nothing here is evaluated against
/// activities yet.
public enum GoalTarget: Sendable, Codable, Hashable {
    /// Cover a distance in a time or faster, e.g. running 5 km in under 20 minutes.
    ///
    /// - `sport`: the sport the distance is covered in.
    /// - `distanceMeters`: the distance, in meters.
    /// - `seconds`: the time to beat, in seconds.
    case time(sport: Sport, distanceMeters: Double, seconds: TimeInterval)
    /// Reach an amount over a recurring period, e.g. running 1500 km per year.
    ///
    /// - `sport`: the sport the amount counts, or `nil` for all sports together.
    /// - `measure`: what is counted.
    /// - `amount`: the amount to reach per period, in meters for ``GoalMeasure/distanceMeters`` and in
    ///   seconds for ``GoalMeasure/durationSeconds``.
    /// - `per`: the period the amount is counted over.
    case volume(sport: Sport?, measure: GoalMeasure, amount: Double, per: GoalPeriod)
    /// A goal in the athlete's own words, with no structured target; ``Goal/name`` and
    /// ``Goal/notes`` say what it is.
    case freeText
}

import Foundation

/// A workout in which the athlete held a heart rate above their current max heart rate, offered
/// as evidence for raising it.
///
/// Produced by ``TrainingModel/maxHeartRateSuggestion(among:detector:)`` and applied (after the athlete
/// confirms) with ``TrainingModel/applyMaxHeartRate(_:asOf:)``. A suggestion only ever raises max
/// heart rate: a workout that stayed below it says nothing about where the true maximum is.
public struct MaxHeartRateSuggestion: Sendable, Hashable {
    /// The ``Activity`` the peak was held in.
    public let activityID: UUID
    /// The activity's sport, for describing it to the athlete.
    public let sport: Sport
    /// The activity's start, which also becomes the new settings' effective date.
    public let activityStart: Date
    /// The held peak, rounded to a whole beat per minute.
    public let peakBPM: Double
    /// The max heart rate currently on record, in beats per minute.
    public let currentMaxBPM: Double

    /// Creates a suggestion.
    ///
    /// - Parameters:
    ///   - activityID: The activity the peak was held in.
    ///   - sport: The activity's sport.
    ///   - activityStart: The activity's start.
    ///   - peakBPM: The held peak, in beats per minute.
    ///   - currentMaxBPM: The max heart rate currently on record, in beats per minute.
    public init(activityID: UUID, sport: Sport, activityStart: Date, peakBPM: Double, currentMaxBPM: Double) {
        self.activityID = activityID
        self.sport = sport
        self.activityStart = activityStart
        self.peakBPM = peakBPM
        self.currentMaxBPM = currentMaxBPM
    }
}

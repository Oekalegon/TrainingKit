import Foundation

/// Why ``WorkoutRanker`` ranks a workout lower than one without the reason (MVP5-155).
public enum WorkoutRankReason: Sendable, Hashable {
    /// With the workout in the plan, the evaluator finds a ``Severity/risk`` of `rule` on `day` that the
    /// plan did not have before.
    case addsRisk(rule: PlanRule, day: Date)
    /// The workout wants more days free around it than its demanding neighbours leave.
    case recoveryDaysShort(neededDays: Int, availableDays: Int)
    /// The micro's phase does not ask for this kind of session (``TrainingParadigm/sessionProfiles``).
    case notAskedInPhase(CyclePhase)
    /// The micro's planned time with the workout is above the volume of the micro, by this many seconds.
    case aboveMicroVolume(by: TimeInterval)
}

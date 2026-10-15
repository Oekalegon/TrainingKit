import Foundation

/// Why a request to link an activity to a plan (``TrainingModel/linkActivity(id:toPlan:asOf:)``)
/// was refused.
public enum PlanLinkError: Error, Sendable, Hashable {
    /// The activity and the plan aren't on the same calendar day in the athlete's time zone. A plan
    /// only ever stands for a workout done on its own day, so a link never crosses days.
    case differentDay
}

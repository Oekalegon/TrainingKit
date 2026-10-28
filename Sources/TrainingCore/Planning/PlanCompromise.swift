import Foundation

/// Something a plan proposal gave up compared with what the athlete asked for, and why (MVP5-120).
///
/// The preview (MVP5-121) lists these next to the warnings so the athlete sees the trade-offs before
/// committing. The first four come from the provider that built the plan, the last from
/// ``PlanAdjuster``.
public enum PlanCompromise: Sendable, Codable, Hashable {
    /// A preference the plan overrides.
    public enum OverriddenPreference: String, Sendable, Codable, Hashable {
        /// ``PlanPreferences/includeConditioning``: the athlete asked for conditioning.
        case includeConditioning
        /// ``PlanPreferences/maxWeeklyVolume``: a micro needed more than the athlete's limit.
        case maxWeeklyVolume
        /// ``PlanPreferences/maxLongRunMeters``: a long run needed more than the athlete's limit.
        case maxLongRun
    }

    /// The lead time was too short for the paradigm's macro; see ``LeadTimeCompromiser``.
    case leadTime(LeadTimeCompromise)
    /// A requested session could not be placed on a day in the micro starting on `microStart`.
    case unplacedSession(microStart: Date, DroppedSession)
    /// No library template meets `profile` for the micro starting on `microStart`; see
    /// ``TemplateFit/missingTemplate(_:)``.
    case missingTemplate(microStart: Date, SessionProfile)
    /// The volume could not bring the micro starting on `microStart` to the TSB zone of its role (MVP5-151):
    /// it ends in `reached` instead of `aimed`. Fresher than aimed means even the athlete's own volume (the
    /// ceiling of the micro) leaves them fresh, so a higher starting or peak volume would be needed; more tired
    /// than aimed means even the lightest volume tried leaves them tired, as after a race or a heavy history.
    /// A micro the adjust loop lowered is not reported here: the adjustment is.
    case sizingMissedZone(microStart: Date, aimed: TSBZone, reached: TSBZone)
    /// A workout wants more days free of demanding workouts around it than the plan could give it, and
    /// no other template fitted better: the workout on `day` made from `template` keeps its place with
    /// `availableDays` instead of `neededDays` days to its nearest demanding neighbour (MVP5-147,
    /// ``RecoveryDays``). The limits are minimums to aim for, so the plan keeps the workout and says so.
    case recoveryDaysShort(day: Date, template: String, neededDays: Int, availableDays: Int)
    /// The plan overrides one of the athlete's preferences.
    case overriddenPreference(OverriddenPreference)
    /// ``PlanAdjuster`` made `adjustment` to clear a ``Severity/risk`` finding of `rule`.
    case adjusted(PlanAdjustment, answering: PlanRule)
}

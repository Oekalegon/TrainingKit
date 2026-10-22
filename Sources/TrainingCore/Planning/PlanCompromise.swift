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
    /// The plan overrides one of the athlete's preferences.
    case overriddenPreference(OverriddenPreference)
    /// ``PlanAdjuster`` made `adjustment` to clear a ``Severity/risk`` finding of `rule`.
    case adjusted(PlanAdjustment, answering: PlanRule)
}

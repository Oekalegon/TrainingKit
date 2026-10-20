/// One change ``LeadTimeCompromiser`` made to the macro because the lead time was too short, and
/// why.
///
/// The generator and the plan proposal (MVP5-120) list these so the athlete sees what was given up.
public struct LeadTimeCompromise: Sendable, Codable, Hashable {
    /// What was changed. Lengths are in micros.
    public enum Action: Sendable, Codable, Hashable {
        /// A whole phase was left out.
        case phaseDropped(CyclePhase)
        /// The paradigm's ``TrainingParadigm/shortenablePhase`` was cut from `fromMicros` to `toMicros`.
        case phaseShortened(CyclePhase, fromMicros: Int, toMicros: Int)
        /// A block was cut from the start of the macro, the oldest first, from `fromMicros` to
        /// `toMicros` (0 when the block was removed). The phases that are never cut stay.
        case oldestPhaseTrimmed(CyclePhase, fromMicros: Int, toMicros: Int)
    }

    /// Why a change was needed.
    public enum Reason: Sendable, Codable, Hashable {
        /// The macro had `neededMicros` micros at this step but the lead time has only
        /// `availableMicros`.
        case leadTimeTooShort(availableMicros: Int, neededMicros: Int)
    }

    /// A ``PlanPreferences`` field a compromise overrode.
    public enum OverriddenPreference: String, Sendable, Codable, Hashable {
        /// ``PlanPreferences/includeConditioning``: the athlete asked for conditioning.
        case includeConditioning
    }

    /// What was changed.
    public var action: Action
    /// Why it was changed.
    public var reason: Reason

    /// The preference this compromise overrode, if any: dropping conditioning overrides
    /// ``PlanPreferences/includeConditioning``, which can only be dropped here if it was `true`.
    /// The other compromises change the paradigm's structure, not a preference, and return `nil`.
    public var overriddenPreference: OverriddenPreference? {
        if case .phaseDropped(let phase) = action, phase == .conditioning { return .includeConditioning }
        return nil
    }

    /// Creates a compromise.
    ///
    /// - Parameters:
    ///   - action: What was changed.
    ///   - reason: Why it was changed.
    public init(action: Action, reason: Reason) {
        self.action = action
        self.reason = reason
    }
}

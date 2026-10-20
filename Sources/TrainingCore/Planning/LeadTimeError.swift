/// Why ``LeadTimeCompromiser`` could not fit a macro into the lead time.
public enum LeadTimeError: Error, Sendable, Hashable {
    /// The micro length is not above zero.
    case invalidMicroLength
    /// The lead time is negative.
    case negativeLeadTime
    /// Even the phases that are never cut (the taper, and the shortenable phase at its minimum)
    /// need more micros than the lead time has, so no plan is possible.
    ///
    /// - Parameters:
    ///   - availableMicros: The whole micros in the lead time.
    ///   - requiredMicros: The micros the taper and the shortest allowed shortenable phase need.
    case leadTimeTooShort(availableMicros: Int, requiredMicros: Int)
}

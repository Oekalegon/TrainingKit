extension PlanGuardrails {
    /// A paradigm's replacements for individual guardrail thresholds.
    ///
    /// Every field is optional; a `nil` field leaves the matching ``PlanGuardrails`` value as it
    /// was. A paradigm that tolerates a lower TSB sets only ``minAcceptableTSB``, for instance.
    /// The fields mirror the thresholds of ``PlanGuardrails`` one to one; see there for their
    /// meaning and units. Missing keys decode as `nil`.
    public struct Overrides: Sendable, Codable, Hashable {
        /// Replaces ``PlanGuardrails/maxMonotony``.
        public var maxMonotony: Double?
        /// Replaces ``PlanGuardrails/maxStrainPercentile``.
        public var maxStrainPercentile: Double?
        /// Replaces ``PlanGuardrails/strainTrailingWindowDays``.
        public var strainTrailingWindowDays: Int?
        /// Replaces ``PlanGuardrails/minTSBOnRaceDay``.
        public var minTSBOnRaceDay: Double?
        /// Replaces ``PlanGuardrails/maxTSBOnRaceDay``.
        public var maxTSBOnRaceDay: Double?
        /// Replaces ``PlanGuardrails/minAcceptableTSB``.
        public var minAcceptableTSB: Double?
        /// Replaces ``PlanGuardrails/maxAcceptableTSB``.
        public var maxAcceptableTSB: Double?
        /// Replaces ``PlanGuardrails/maxBuildProgressionFraction``.
        public var maxBuildProgressionFraction: Double?

        /// Creates a set of overrides; every parameter defaults to `nil` (no replacement).
        public init(
            maxMonotony: Double? = nil,
            maxStrainPercentile: Double? = nil,
            strainTrailingWindowDays: Int? = nil,
            minTSBOnRaceDay: Double? = nil,
            maxTSBOnRaceDay: Double? = nil,
            minAcceptableTSB: Double? = nil,
            maxAcceptableTSB: Double? = nil,
            maxBuildProgressionFraction: Double? = nil
        ) {
            self.maxMonotony = maxMonotony
            self.maxStrainPercentile = maxStrainPercentile
            self.strainTrailingWindowDays = strainTrailingWindowDays
            self.minTSBOnRaceDay = minTSBOnRaceDay
            self.maxTSBOnRaceDay = maxTSBOnRaceDay
            self.minAcceptableTSB = minAcceptableTSB
            self.maxAcceptableTSB = maxAcceptableTSB
            self.maxBuildProgressionFraction = maxBuildProgressionFraction
        }

        /// `guardrails` with every non-`nil` override applied.
        ///
        /// - Parameter guardrails: The guardrails to start from.
        /// - Returns: A copy of `guardrails`; fields whose override is `nil` are unchanged.
        public func applied(to guardrails: PlanGuardrails) -> PlanGuardrails {
            var result = guardrails
            result.maxMonotony = maxMonotony ?? result.maxMonotony
            result.maxStrainPercentile = maxStrainPercentile ?? result.maxStrainPercentile
            result.strainTrailingWindowDays = strainTrailingWindowDays ?? result.strainTrailingWindowDays
            result.minTSBOnRaceDay = minTSBOnRaceDay ?? result.minTSBOnRaceDay
            result.maxTSBOnRaceDay = maxTSBOnRaceDay ?? result.maxTSBOnRaceDay
            result.minAcceptableTSB = minAcceptableTSB ?? result.minAcceptableTSB
            result.maxAcceptableTSB = maxAcceptableTSB ?? result.maxAcceptableTSB
            result.maxBuildProgressionFraction = maxBuildProgressionFraction ?? result.maxBuildProgressionFraction
            return result
        }
    }
}

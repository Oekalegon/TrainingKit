/// Tunable thresholds ``PlanEvaluator`` checks a plan's projected metrics against.
///
/// `Codable` and user-editable; MVP 3 can tune these from observed outcomes (e.g. an athlete who
/// tolerates a lower TSB without issue).
public struct PlanGuardrails: Sendable, Codable, Hashable {
    /// Trailing-window mean/stdev above which a week has no easy/hard contrast, even at moderate
    /// volume.
    public var maxMonotony: Double
    /// The percentile within the athlete's own trailing ``strainTrailingWindowDays`` of strain
    /// values above which a day's strain is flagged — absolute TRIMP thresholds don't transfer
    /// across athletes, so this compares against the athlete's own distribution instead.
    public var maxStrainPercentile: Double
    /// How many days of trailing strain history to compare a day against for
    /// ``maxStrainPercentile``; defaults to 84 (12 weeks).
    public var strainTrailingWindowDays: Int
    /// The lowest acceptable TSB on race day — below this, the taper hasn't landed.
    public var minTSBOnRaceDay: Double
    /// The highest acceptable TSB on race day — above this, fitness was lost in the taper.
    public var maxTSBOnRaceDay: Double
    /// The lowest acceptable TSB on *any* day — below this is the injury-risk band, independent of
    /// whether the plan has any known phase to judge ``maxATLtoCTLRatio``/``minATLtoCTLRatio``
    /// against. Deliberately looser than ``minTSBOnRaceDay``: a normal build phase routinely dips
    /// well below race-day freshness without that being a problem.
    public var minAcceptableTSB: Double
    /// The highest acceptable TSB on *any* day — above this for a sustained period reads as
    /// detraining (fitness being lost to insufficient load), the same freshness-band check as
    /// ``maxTSBOnRaceDay`` but not gated on it being a race day.
    public var maxAcceptableTSB: Double
    /// The minimum CTL gain expected across a base/build mesocycle — guards against a "safe" plan
    /// that's actually flat.
    public var minCTLGainPerMeso: Double
    /// How many days of consecutive non-recovery micros are acceptable before the next
    /// non-recovery micro is flagged, e.g. 21 for a 3:1 pattern of 7-day micros. In days rather
    /// than micros so it means the same for 7-, 10- and 14-day micros.
    public var maxDaysWithoutRecovery: Int
    /// A recovery micro's mean daily load, as a fraction of the micro before it, above which the
    /// recovery micro didn't actually recover.
    public var recoveryLoadFraction: Double
    /// The fractional increase in mean daily load from one build micro to the next above which the
    /// progression is too aggressive.
    public var maxBuildProgressionFraction: Double
    /// The fractional CTL drop across a taper mesocycle above which too much fitness was lost.
    public var maxTaperCTLDropFraction: Double

    /// Creates a set of plan guardrails, defaulting to the values discussed in the design doc.
    ///
    /// - Parameters:
    ///   - maxMonotony: Trailing-window mean/stdev above which a week lacks easy/hard contrast;
    ///     defaults to 2.0.
    ///   - maxStrainPercentile: The trailing-distribution percentile above which a day's strain is
    ///     flagged; defaults to 0.95.
    ///   - strainTrailingWindowDays: How many days of trailing strain history to compare against;
    ///     defaults to 84.
    ///   - minTSBOnRaceDay: The lowest acceptable TSB on race day; defaults to 5.
    ///   - maxTSBOnRaceDay: The highest acceptable TSB on race day; defaults to 25.
    ///   - minAcceptableTSB: The lowest acceptable TSB on any day; defaults to -30.
    ///   - maxAcceptableTSB: The highest acceptable TSB on any day; defaults to 25.
    ///   - minCTLGainPerMeso: The minimum CTL gain expected across a base/build meso; defaults to 2.
    ///   - maxDaysWithoutRecovery: How many days of consecutive non-recovery micros are
    ///     acceptable; defaults to 21.
    ///   - recoveryLoadFraction: A recovery micro's mean daily load, as a fraction of the prior
    ///     micro's, above which it didn't actually recover; defaults to 0.65.
    ///   - maxBuildProgressionFraction: The fractional increase in mean daily load between build
    ///     micros above which the progression is too aggressive; defaults to 0.10.
    ///   - maxTaperCTLDropFraction: The fractional CTL drop across a taper meso above which too
    ///     much fitness was lost; defaults to 0.10.
    public init(
        maxMonotony: Double = 2.0,
        maxStrainPercentile: Double = 0.95,
        strainTrailingWindowDays: Int = 84,
        minTSBOnRaceDay: Double = 5,
        maxTSBOnRaceDay: Double = 25,
        minAcceptableTSB: Double = -30,
        maxAcceptableTSB: Double = 25,
        minCTLGainPerMeso: Double = 2,
        maxDaysWithoutRecovery: Int = 21,
        recoveryLoadFraction: Double = 0.65,
        maxBuildProgressionFraction: Double = 0.10,
        maxTaperCTLDropFraction: Double = 0.10
    ) {
        self.maxMonotony = maxMonotony
        self.maxStrainPercentile = maxStrainPercentile
        self.strainTrailingWindowDays = strainTrailingWindowDays
        self.minTSBOnRaceDay = minTSBOnRaceDay
        self.maxTSBOnRaceDay = maxTSBOnRaceDay
        self.minAcceptableTSB = minAcceptableTSB
        self.maxAcceptableTSB = maxAcceptableTSB
        self.minCTLGainPerMeso = minCTLGainPerMeso
        self.maxDaysWithoutRecovery = maxDaysWithoutRecovery
        self.recoveryLoadFraction = recoveryLoadFraction
        self.maxBuildProgressionFraction = maxBuildProgressionFraction
        self.maxTaperCTLDropFraction = maxTaperCTLDropFraction
    }

    private enum CodingKeys: String, CodingKey {
        case maxMonotony
        case maxStrainPercentile, strainTrailingWindowDays, minTSBOnRaceDay, maxTSBOnRaceDay
        case minAcceptableTSB, maxAcceptableTSB, minCTLGainPerMeso, maxDaysWithoutRecovery
        case recoveryLoadFraction, maxBuildProgressionFraction, maxTaperCTLDropFraction
        /// The pre-MVP5-101 key: a count of 7-day micros, read as `count * 7` days.
        case maxMicrosWithoutRecovery
    }

    /// Decodes guardrails, ignoring the keys of the removed CTL-ramp and ATL/CTL-ratio guardrails
    /// if present, and reading a stored `maxMicrosWithoutRecovery` (a count of micros, from
    /// before the threshold was in days) as that many 7-day micros.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxMonotony = try c.decode(Double.self, forKey: .maxMonotony)
        maxStrainPercentile = try c.decode(Double.self, forKey: .maxStrainPercentile)
        strainTrailingWindowDays = try c.decode(Int.self, forKey: .strainTrailingWindowDays)
        minTSBOnRaceDay = try c.decode(Double.self, forKey: .minTSBOnRaceDay)
        maxTSBOnRaceDay = try c.decode(Double.self, forKey: .maxTSBOnRaceDay)
        minAcceptableTSB = try c.decode(Double.self, forKey: .minAcceptableTSB)
        maxAcceptableTSB = try c.decode(Double.self, forKey: .maxAcceptableTSB)
        minCTLGainPerMeso = try c.decode(Double.self, forKey: .minCTLGainPerMeso)
        if let days = try c.decodeIfPresent(Int.self, forKey: .maxDaysWithoutRecovery) {
            maxDaysWithoutRecovery = days
        } else {
            maxDaysWithoutRecovery = try c.decode(Int.self, forKey: .maxMicrosWithoutRecovery) * 7
        }
        recoveryLoadFraction = try c.decode(Double.self, forKey: .recoveryLoadFraction)
        maxBuildProgressionFraction = try c.decode(Double.self, forKey: .maxBuildProgressionFraction)
        maxTaperCTLDropFraction = try c.decode(Double.self, forKey: .maxTaperCTLDropFraction)
    }

    /// Encodes guardrails with `maxDaysWithoutRecovery`; the legacy key is only ever read.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxMonotony, forKey: .maxMonotony)
        try c.encode(maxStrainPercentile, forKey: .maxStrainPercentile)
        try c.encode(strainTrailingWindowDays, forKey: .strainTrailingWindowDays)
        try c.encode(minTSBOnRaceDay, forKey: .minTSBOnRaceDay)
        try c.encode(maxTSBOnRaceDay, forKey: .maxTSBOnRaceDay)
        try c.encode(minAcceptableTSB, forKey: .minAcceptableTSB)
        try c.encode(maxAcceptableTSB, forKey: .maxAcceptableTSB)
        try c.encode(minCTLGainPerMeso, forKey: .minCTLGainPerMeso)
        try c.encode(maxDaysWithoutRecovery, forKey: .maxDaysWithoutRecovery)
        try c.encode(recoveryLoadFraction, forKey: .recoveryLoadFraction)
        try c.encode(maxBuildProgressionFraction, forKey: .maxBuildProgressionFraction)
        try c.encode(maxTaperCTLDropFraction, forKey: .maxTaperCTLDropFraction)
    }
}

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
    /// whether the plan has any known phase to judge it against. Deliberately looser than
    /// ``minTSBOnRaceDay``: a normal build phase routinely dips well below race-day freshness
    /// without that being a problem.
    public var minAcceptableTSB: Double
    /// The highest acceptable TSB on *any* day — above this for a sustained period reads as
    /// detraining (fitness being lost to insufficient load), the same freshness-band check as
    /// ``maxTSBOnRaceDay`` but not gated on it being a race day.
    public var maxAcceptableTSB: Double
    /// The fractional increase of a run over the longest run of the previous 28 days above which
    /// the run is too much of a jump (0.10 allows 10 % more).
    public var maxLongestRunIncreaseFraction: Double

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
    ///   - maxLongestRunIncreaseFraction: The fractional increase of a run over the longest run of
    ///     the previous 28 days above which it is flagged; defaults to 0.10.
    public init(
        maxMonotony: Double = 2.0,
        maxStrainPercentile: Double = 0.95,
        strainTrailingWindowDays: Int = 84,
        minTSBOnRaceDay: Double = 5,
        maxTSBOnRaceDay: Double = 25,
        minAcceptableTSB: Double = -30,
        maxAcceptableTSB: Double = 25,
        maxLongestRunIncreaseFraction: Double = 0.10
    ) {
        self.maxMonotony = maxMonotony
        self.maxStrainPercentile = maxStrainPercentile
        self.strainTrailingWindowDays = strainTrailingWindowDays
        self.minTSBOnRaceDay = minTSBOnRaceDay
        self.maxTSBOnRaceDay = maxTSBOnRaceDay
        self.minAcceptableTSB = minAcceptableTSB
        self.maxAcceptableTSB = maxAcceptableTSB
        self.maxLongestRunIncreaseFraction = maxLongestRunIncreaseFraction
    }

    private enum CodingKeys: String, CodingKey {
        case maxMonotony, maxStrainPercentile, strainTrailingWindowDays, minTSBOnRaceDay, maxTSBOnRaceDay
        case minAcceptableTSB, maxAcceptableTSB, maxLongestRunIncreaseFraction
    }

    /// Decodes guardrails; a missing value (for instance `maxLongestRunIncreaseFraction` in a
    /// payload from before it existed) takes its default, and the removed
    /// `maxBuildProgressionFraction` is ignored.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PlanGuardrails()
        maxMonotony = try container.decodeIfPresent(Double.self, forKey: .maxMonotony) ?? defaults.maxMonotony
        maxStrainPercentile = try container.decodeIfPresent(Double.self, forKey: .maxStrainPercentile) ?? defaults.maxStrainPercentile
        strainTrailingWindowDays = try container.decodeIfPresent(Int.self, forKey: .strainTrailingWindowDays) ?? defaults.strainTrailingWindowDays
        minTSBOnRaceDay = try container.decodeIfPresent(Double.self, forKey: .minTSBOnRaceDay) ?? defaults.minTSBOnRaceDay
        maxTSBOnRaceDay = try container.decodeIfPresent(Double.self, forKey: .maxTSBOnRaceDay) ?? defaults.maxTSBOnRaceDay
        minAcceptableTSB = try container.decodeIfPresent(Double.self, forKey: .minAcceptableTSB) ?? defaults.minAcceptableTSB
        maxAcceptableTSB = try container.decodeIfPresent(Double.self, forKey: .maxAcceptableTSB) ?? defaults.maxAcceptableTSB
        maxLongestRunIncreaseFraction = try container.decodeIfPresent(Double.self, forKey: .maxLongestRunIncreaseFraction) ?? defaults.maxLongestRunIncreaseFraction
    }
}

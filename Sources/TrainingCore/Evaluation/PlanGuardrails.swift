/// Tunable thresholds ``PlanEvaluator`` checks a plan's projected metrics against.
///
/// `Codable` and user-editable; MVP 3 can tune these from observed outcomes (e.g. an athlete who
/// tolerates a 1.5 ATL/CTL ratio without issue).
public struct PlanGuardrails: Sendable, Codable, Hashable {
    /// CTL points gained per 7 days above which fitness is climbing too fast — the classic
    /// overuse setup; fellrnr and Coggan both flag ~5–8/week as the ceiling for most runners.
    public var maxCTLRampPerWeek: Double
    /// The acute:chronic workload ratio analogue (ATL/CTL) above which is the injury-risk band.
    public var maxATLtoCTLRatio: Double
    /// The ATL/CTL ratio below which the plan is losing fitness rather than at risk — flagged as
    /// ``Severity/warning``, not ``Severity/risk``.
    public var minATLtoCTLRatio: Double
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
    /// The minimum CTL gain expected across a base/build mesocycle — guards against a "safe" plan
    /// that's actually flat.
    public var minCTLGainPerMeso: Double
    /// How many consecutive non-recovery micros are acceptable before flagging, e.g. 3 for a 3:1
    /// pattern.
    public var maxMicrosWithoutRecovery: Int
    /// A recovery micro's load, as a fraction of the micro before it, above which the recovery
    /// micro didn't actually recover.
    public var recoveryLoadFraction: Double
    /// The fractional load increase from one build micro to the next above which the progression
    /// is too aggressive.
    public var maxBuildProgressionFraction: Double
    /// The fractional CTL drop across a taper mesocycle above which too much fitness was lost.
    public var maxTaperCTLDropFraction: Double

    /// Creates a set of plan guardrails, defaulting to the values discussed in the design doc.
    ///
    /// - Parameters:
    ///   - maxCTLRampPerWeek: CTL points gained per 7 days above which fitness is climbing too
    ///     fast; defaults to 6.
    ///   - maxATLtoCTLRatio: The ATL/CTL ratio above which is the injury-risk band; defaults to 1.4.
    ///   - minATLtoCTLRatio: The ATL/CTL ratio below which the plan is losing fitness; defaults to 0.7.
    ///   - maxMonotony: Trailing-window mean/stdev above which a week lacks easy/hard contrast;
    ///     defaults to 2.0.
    ///   - maxStrainPercentile: The trailing-distribution percentile above which a day's strain is
    ///     flagged; defaults to 0.95.
    ///   - strainTrailingWindowDays: How many days of trailing strain history to compare against;
    ///     defaults to 84.
    ///   - minTSBOnRaceDay: The lowest acceptable TSB on race day; defaults to 5.
    ///   - maxTSBOnRaceDay: The highest acceptable TSB on race day; defaults to 25.
    ///   - minCTLGainPerMeso: The minimum CTL gain expected across a base/build meso; defaults to 2.
    ///   - maxMicrosWithoutRecovery: How many consecutive non-recovery micros are acceptable;
    ///     defaults to 3.
    ///   - recoveryLoadFraction: A recovery micro's load, as a fraction of the prior micro's,
    ///     above which it didn't actually recover; defaults to 0.65.
    ///   - maxBuildProgressionFraction: The fractional load increase between build micros above
    ///     which the progression is too aggressive; defaults to 0.10.
    ///   - maxTaperCTLDropFraction: The fractional CTL drop across a taper meso above which too
    ///     much fitness was lost; defaults to 0.10.
    public init(
        maxCTLRampPerWeek: Double = 6,
        maxATLtoCTLRatio: Double = 1.4,
        minATLtoCTLRatio: Double = 0.7,
        maxMonotony: Double = 2.0,
        maxStrainPercentile: Double = 0.95,
        strainTrailingWindowDays: Int = 84,
        minTSBOnRaceDay: Double = 5,
        maxTSBOnRaceDay: Double = 25,
        minCTLGainPerMeso: Double = 2,
        maxMicrosWithoutRecovery: Int = 3,
        recoveryLoadFraction: Double = 0.65,
        maxBuildProgressionFraction: Double = 0.10,
        maxTaperCTLDropFraction: Double = 0.10
    ) {
        self.maxCTLRampPerWeek = maxCTLRampPerWeek
        self.maxATLtoCTLRatio = maxATLtoCTLRatio
        self.minATLtoCTLRatio = minATLtoCTLRatio
        self.maxMonotony = maxMonotony
        self.maxStrainPercentile = maxStrainPercentile
        self.strainTrailingWindowDays = strainTrailingWindowDays
        self.minTSBOnRaceDay = minTSBOnRaceDay
        self.maxTSBOnRaceDay = maxTSBOnRaceDay
        self.minCTLGainPerMeso = minCTLGainPerMeso
        self.maxMicrosWithoutRecovery = maxMicrosWithoutRecovery
        self.recoveryLoadFraction = recoveryLoadFraction
        self.maxBuildProgressionFraction = maxBuildProgressionFraction
        self.maxTaperCTLDropFraction = maxTaperCTLDropFraction
    }
}

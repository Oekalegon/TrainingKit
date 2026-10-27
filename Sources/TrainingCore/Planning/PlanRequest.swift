import Foundation

/// Everything ``PlanGenerator`` needs to build a plan proposal (MVP5-145).
///
/// The request carries every choice that belongs to the athlete or the app (the layout templates,
/// the volumes, the session counts); the generator adds no numbers of its own. It is not stored.
public struct PlanRequest: Sendable {
    /// The race the plan builds towards. Its date ends the last micro and its
    /// ``Race/specificPhaseTarget`` aims the step targets.
    public var targetRace: Race
    /// The other races in the window. Secondary ones shape the layout (``KeyRaceLayout``); all of them
    /// are checked for race-day TSB.
    public var otherRaces: [Race]
    /// The paradigm whose rules, session profiles and hard-session definition apply.
    public var paradigm: TrainingParadigm
    /// The full-length macro for `paradigm`, before the lead time shortens it
    /// (``LeadTimeCompromiser``). The generator does not choose phase lengths.
    public var macro: MacroTemplate
    /// The meso pattern, which also sets the micro length in days (7, 10 or 14).
    public var meso: MesocycleTemplate
    /// The athlete's wishes: availability, maximum weekly volume, conditioning.
    public var preferences: PlanPreferences
    /// The athlete: time zone, zones and pace model for step targets and load estimates.
    public var athlete: AthleteProfile
    /// The current day. The projected series treats days before it as done and from it on as planned;
    /// nothing in the generator reads the clock.
    public var today: Date
    /// The first day of the plan (at or after `today` in normal use).
    public var start: Date
    /// The library the template fitter chooses from.
    public var templates: [WorkoutTemplate]
    /// The weekly volume at the first build micro, in ``VolumeMeasure/durationSeconds`` per 7 days.
    public var startingVolume: VolumeTarget
    /// The weekly volume at the last build micro, in ``VolumeMeasure/durationSeconds`` per 7 days;
    /// lowered to ``PlanPreferences/maxWeeklyVolume`` for running if that is lower.
    public var peakVolume: VolumeTarget
    /// How many hard sessions each micro asks the day assigner for (every micro, whatever its role).
    /// By default ``defaultHardSessionsPerMicro(microLengthDays:)`` for the micro length of `meso`.
    public var hardSessionsPerMicro: Int
    /// How many long runs each micro asks the day assigner for (every micro, whatever its role).
    public var longRunsPerMicro: Int
    /// The athlete's past activities, which seed the projected series. Without history the first
    /// ``LoadModelParameters/ctlTimeConstantDays`` days are warming up and the TSB rules skip them.
    public var activities: [Activity]
    /// Past planned or performed runs, as ``PlanEvaluator`` sees them, for the longest-run rule of the
    /// first weeks.
    public var recentSessions: [PlanSession]
    /// The thresholds to evaluate against.
    public var guardrails: PlanGuardrails
    /// How many micros the secondary races take before and after them.
    public var keyRaceLayout: KeyRaceLayout
    /// Fits a paradigm's macro into a short lead time.
    public var leadTimeCompromiser: LeadTimeCompromiser
    /// Turns the starting and peak volume into a volume per micro.
    public var volumeCurve: VolumeCurveBuilder

    /// The hard sessions a micro of `microLengthDays` days asks for by default: 2 for 7 days, 3 for 10
    /// and 4 for 14, which is 2 per 7 days rounded to a whole number.
    ///
    /// - Parameter microLengthDays: The micro length in days.
    public static func defaultHardSessionsPerMicro(microLengthDays: Int) -> Int {
        max(Int((Double(microLengthDays) * 2 / 7).rounded()), 0)
    }

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - targetRace: The race the plan builds towards.
    ///   - otherRaces: The other races in the window; defaults to none.
    ///   - paradigm: The paradigm that applies.
    ///   - macro: The full-length macro for the paradigm.
    ///   - meso: The meso pattern and micro length.
    ///   - preferences: The athlete's wishes; defaults to none.
    ///   - athlete: The athlete.
    ///   - today: The current day.
    ///   - start: The first day of the plan.
    ///   - templates: The workout templates to choose from.
    ///   - startingVolume: Seconds per 7 days at the first build micro.
    ///   - peakVolume: Seconds per 7 days at the last build micro.
    ///   - hardSessionsPerMicro: Hard sessions asked per micro; defaults to `nil`, which asks
    ///     ``defaultHardSessionsPerMicro(microLengthDays:)`` for the micro length of `meso`.
    ///   - longRunsPerMicro: Long runs asked per micro; defaults to 1.
    ///   - activities: The past activities; defaults to none.
    ///   - recentSessions: Past runs for the longest-run rule; defaults to none.
    ///   - guardrails: The thresholds; defaults to ``PlanGuardrails``'s defaults.
    ///   - keyRaceLayout: The secondary-race taper and recovery; defaults to 1 and 1 micros.
    ///   - leadTimeCompromiser: The lead-time step; defaults to its defaults.
    ///   - volumeCurve: The volume curve; defaults to its defaults.
    public init(
        targetRace: Race,
        otherRaces: [Race] = [],
        paradigm: TrainingParadigm,
        macro: MacroTemplate,
        meso: MesocycleTemplate,
        preferences: PlanPreferences = PlanPreferences(),
        athlete: AthleteProfile,
        today: Date,
        start: Date,
        templates: [WorkoutTemplate],
        startingVolume: VolumeTarget,
        peakVolume: VolumeTarget,
        hardSessionsPerMicro: Int? = nil,
        longRunsPerMicro: Int = 1,
        activities: [Activity] = [],
        recentSessions: [PlanSession] = [],
        guardrails: PlanGuardrails = PlanGuardrails(),
        keyRaceLayout: KeyRaceLayout = KeyRaceLayout(),
        leadTimeCompromiser: LeadTimeCompromiser = LeadTimeCompromiser(),
        volumeCurve: VolumeCurveBuilder = VolumeCurveBuilder()
    ) {
        self.targetRace = targetRace
        self.otherRaces = otherRaces
        self.paradigm = paradigm
        self.macro = macro
        self.meso = meso
        self.preferences = preferences
        self.athlete = athlete
        self.today = today
        self.start = start
        self.templates = templates
        self.startingVolume = startingVolume
        self.peakVolume = peakVolume
        self.hardSessionsPerMicro = hardSessionsPerMicro ?? Self.defaultHardSessionsPerMicro(microLengthDays: meso.microLengthDays)
        self.longRunsPerMicro = longRunsPerMicro
        self.activities = activities
        self.recentSessions = recentSessions
        self.guardrails = guardrails
        self.keyRaceLayout = keyRaceLayout
        self.leadTimeCompromiser = leadTimeCompromiser
        self.volumeCurve = volumeCurve
    }
}

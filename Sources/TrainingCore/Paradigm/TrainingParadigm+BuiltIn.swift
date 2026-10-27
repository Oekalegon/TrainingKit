extension TrainingParadigm {
    /// 80/20 polarized training (Fitzgerald, *80/20 Running*): about 80 % of planned time easy and
    /// about 20 % hard, with little in between.
    ///
    /// - Phases: base, build, peak, taper.
    /// - Distribution (per micro): ``IntensityCategory/high`` 0.2 and ``IntensityCategory/medium`` 0,
    ///   tolerance 0.05, except build (`high` 0.22) and peak (`high` 0.25), which allow a little
    ///   and more hard time. ``IntensityCategory/low`` and
    ///   ``IntensityCategory/veryLow`` are left unlisted, so both count as the easy remainder.
    /// - Hard: intensity of ``IntensityCategory/high`` or more; speed is ignored.
    /// - Spacing: at least 2 days between hard sessions, so never on consecutive days. Long runs
    ///   are spaced like hard sessions (``spacesLongRunsAsHard``).
    /// - Hard sessions per micro: at most 2 in a 7-day micro, 3 in 10 days, 4 in 14 days.
    ///
    /// These numbers were reviewed and set (MVP5-136): they are the product's own choices, not
    /// taken from a source, apart from the 80/20 split itself. A micro's shares count each
    /// session's whole planned time under its one intensity category, so a hard session's warm-up
    /// and cool-down count as hard time.
    public static let polarized8020 = TrainingParadigm(
        name: "80/20 polarized",
        phases: [.base, .build, .peak, .taper],
        defaultMix: IntensityMix(intensityShares: [.high: 0.2, .medium: 0], tolerance: 0.05),
        phaseMixes: [
            .build: IntensityMix(intensityShares: [.high: 0.22, .medium: 0], tolerance: 0.05),
            .peak: IntensityMix(intensityShares: [.high: 0.25, .medium: 0], tolerance: 0.05),
        ],
        hardIntensity: .high,
        spacesLongRunsAsHard: true,
        minDaysBetweenHardSessions: 2,
        maxHardSessionsPerMicro: [7: 2, 10: 3, 14: 4],
        maxBackToBackLongRunPairsPerMicro: [7: 1, 10: 1, 14: 2],
        shortenablePhase: .peak
    )

    /// Triphasic training (Andrew Snow, *Run Elite*): conditioning, base, structural, specific and
    /// taper phases.
    ///
    /// The mixes, tolerances and spacing were reviewed with the user and set on 2026-10-22
    /// (MVP5-137) against the Run Elite skills (`docs/design/triphasic-design.md`); the per-phase
    /// session profiles (interval work lengths, race-target fractions) are the generator's.
    /// Its numbers are calibrated for a marathon (``TrainingParadigm/calibratedDistanceMeters``), so a
    /// shorter target race gets a ``CalibrationWarning`` (MVP5-143).
    /// - Phases: ``CyclePhase/conditioning``, ``CyclePhase/base``, ``CyclePhase/structural``,
    ///   ``CyclePhase/specific``, ``CyclePhase/taper``.
    /// - Distribution: conditioning and base have only easy running, so `medium` and `high`
    ///   intensity are 0 (tolerance 0.05). Conditioning also allows no `moderate`, `fast` or
    ///   `max` speed; base allows slow running and max-speed sprints, but no `moderate` or `fast`
    ///   work (0, tolerance 0.05, so at least 95 % at the two extremes). A max-speed sprint session
    ///   has no ceiling in base: the skills give none.
    ///   Structural: `high` 0.10, `medium` 0, speed `fast` 0.10, `moderate` 0, tolerance 0.10, so
    ///   at most 20 % `high` or `fast` (the skills: at least 80 % at easy pace) and at most 10 %
    ///   `medium` or `moderate` (no race pace); `max` is unlisted, so sprints in easy runs are
    ///   allowed. Specific and taper: `medium` and `high` 0.25 and speed `moderate` and `fast` 0.25,
    ///   tolerance 0.25, so each is at most 50 % (the skills: most miles very easy); the taper keeps
    ///   the specific mix because the skills only say to keep intensity.
    /// - Hard: intensity of ``IntensityCategory/high`` or more, or ``SpeedLevel/max`` speed, so an
    ///   easy session of maximal 8-second sprints is placed like a hard day.
    /// - Spacing: at least 2 days between hard sessions (Tuesday to Thursday: one easy day in
    ///   between); long runs are spaced like hard sessions. The skills give no spacing for the base and
    ///   structural work; the plan can ask for more (``PlanPreferences/minDaysBetweenHardSessions``).
    /// - Hard sessions per micro: no limit; the athlete sets the number of sessions per micro.
    /// - Session profiles, only what the skills decide: base hill sprints of at most 8 s; structural
    ///   fast quality (work lengths from 60 s to 130 s, 114 % of race speed drifting to 106 %) and
    ///   endurance quality (150 s to 2600 s, 86 % drifting to 94 %), one of each per two hard
    ///   sessions; specific and taper work at race pace (100 %). The work lengths are the book's
    ///   worked examples (design doc, Q1); the specific work lengths and the share of race pace are
    ///   open (Q3), so none is set.
    public static let triphasic = TrainingParadigm(
        name: "Triphasic",
        phases: [.conditioning, .base, .structural, .specific, .taper],
        phaseMixes: [
            .conditioning: IntensityMix(
                intensityShares: [.medium: 0, .high: 0],
                speedShares: [.moderate: 0, .fast: 0, .max: 0],
                tolerance: 0.05
            ),
            .base: IntensityMix(
                intensityShares: [.medium: 0, .high: 0],
                speedShares: [.moderate: 0, .fast: 0],
                tolerance: 0.05
            ),
            .structural: IntensityMix(
                intensityShares: [.medium: 0, .high: 0.10],
                speedShares: [.moderate: 0, .fast: 0.10],
                tolerance: 0.10
            ),
            .specific: Self.triphasicKeyWorkoutMix,
            .taper: Self.triphasicKeyWorkoutMix,
        ],
        hardIntensity: .high,
        hardSpeed: .max,
        spacesLongRunsAsHard: true,
        minDaysBetweenHardSessions: 2,
        maxBackToBackLongRunPairsPerMicro: [7: 1, 10: 1, 14: 2],
        shortenablePhase: .specific,
        sessionProfiles: [
            .base: [SessionProfile(sessionType: .hillRepeats, workLength: 0...8)],
            .structural: [
                SessionProfile(sessionType: .interval, workLength: 60...130, raceTargetFraction: 1.14, endRaceTargetFraction: 1.06),
                SessionProfile(sessionType: .interval, workLength: 150...2600, raceTargetFraction: 0.86, endRaceTargetFraction: 0.94),
            ],
            .specific: [SessionProfile(sessionType: .interval, raceTargetFraction: 1.0)],
            .taper: [SessionProfile(sessionType: .interval, raceTargetFraction: 1.0)],
        ],
        calibratedDistanceMeters: Race.marathonDistanceMeters
    )

    /// The mix of specific and taper: `medium` and `high` intensity and `moderate` and `fast` speed
    /// each 0.25 ± 0.25, so none is more than half the time.
    private static let triphasicKeyWorkoutMix = IntensityMix(
        intensityShares: [.medium: 0.25, .high: 0.25],
        speedShares: [.moderate: 0.25, .fast: 0.25],
        tolerance: 0.25
    )

    /// The built-in paradigms: ``polarized8020`` and ``triphasic``.
    public static let builtIn: [TrainingParadigm] = [.polarized8020, .triphasic]
}

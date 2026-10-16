extension TrainingParadigm {
    /// 80/20 polarized training (Fitzgerald, *80/20 Running*): about 80 % of planned time easy and
    /// about 20 % hard, with little in between.
    ///
    /// - Phases: base, build, peak, taper.
    /// - Distribution (every phase, per micro): ``IntensityCategory/high`` 0.2 and
    ///   ``IntensityCategory/medium`` 0, tolerance 0.05. ``IntensityCategory/low`` and
    ///   ``IntensityCategory/veryLow`` are left unlisted, so both count as the easy remainder.
    /// - Hard: intensity of ``IntensityCategory/high`` or more; speed is ignored.
    /// - Spacing: at least 2 days between hard sessions, so never on consecutive days. Long runs
    ///   are easy, so back-to-back long runs are not affected.
    /// - Hard sessions per micro: at most 2 in a 7-day micro, 3 in 10 days, 4 in 14 days.
    public static let polarized8020 = TrainingParadigm(
        name: "80/20 polarized",
        phases: [.base, .build, .peak, .taper],
        defaultMix: IntensityMix(intensityShares: [.high: 0.2, .medium: 0], tolerance: 0.05),
        hardIntensity: .high,
        minDaysBetweenHardSessions: 2,
        maxHardSessionsPerMicro: [7: 2, 10: 3, 14: 4]
    )

    /// Triphasic training (Andrew Snow, *Run Elite*): conditioning, base, structural, specific and
    /// taper phases.
    ///
    /// Only what is settled is encoded; the per-phase session profiles (interval work lengths,
    /// race-target fractions) are MVP5-100 and the generator's.
    /// - Phases: ``CyclePhase/conditioning``, ``CyclePhase/base``, ``CyclePhase/structural``,
    ///   ``CyclePhase/specific``, ``CyclePhase/taper``.
    /// - Distribution: conditioning and base have only easy running, so `medium` and `high`
    ///   intensity are 0 (tolerance 0.05). Conditioning also allows no `moderate`, `fast` or
    ///   `max` speed; base allows slow running and max-speed sprints, but no `moderate` or `fast`
    ///   work. Structural, specific and taper have no target yet.
    /// - Hard: intensity of ``IntensityCategory/high`` or more, or ``SpeedLevel/max`` speed, so an
    ///   easy session of maximal 8-second sprints is placed like a hard day.
    /// - Spacing: at least 2 days between hard sessions.
    /// - Hard sessions per micro: no limit; the athlete sets the number of sessions per micro.
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
        ],
        hardIntensity: .high,
        hardSpeed: .max,
        minDaysBetweenHardSessions: 2
    )

    /// The built-in paradigms: ``polarized8020`` and ``triphasic``.
    public static let builtIn: [TrainingParadigm] = [.polarized8020, .triphasic]
}

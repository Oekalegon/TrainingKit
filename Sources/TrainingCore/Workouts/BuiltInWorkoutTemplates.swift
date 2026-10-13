import Foundation

/// The workout templates shipped with the app, available in every athlete's library without
/// needing to be created by hand.
public enum BuiltInWorkoutTemplates {
    /// A steady Zone 1 run whose duration is the only variable.
    public static let recoveryRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A01")!,
        name: "Recovery run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "duration", name: "Duration", unit: .minutes, defaultValue: 20 * 60, range: 10 * 60...40 * 60
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// A Zone 2 run bracketed by a fixed 5-minute Zone 1 warmup and cooldown, with the main
    /// Zone 2 duration as the only variable.
    public static let easyRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A02")!,
        name: "Easy run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "duration", name: "Duration", unit: .minutes, defaultValue: 30 * 60, range: 15 * 60...60 * 60
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// A Zone 2 run bracketed by a fixed 5-minute Zone 1 warmup and cooldown, with the main
    /// Zone 2 distance as the only variable.
    public static let longRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A03")!,
        name: "Long run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "distance", name: "Distance", unit: .meters, defaultValue: 20_000, range: 10_000...35_000
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// A Zone 3 tempo effort ramped into and out of via fixed Zone 1/Zone 2 segments, with the
    /// main Zone 3 duration as the only variable.
    ///
    /// Only the leading Zone 1 block is `.warmup` and only the trailing Zone 1 block is
    /// `.cooldown` — ``WorkoutKitBridge`` extracts at most one single-step edge block per side into
    /// `CustomWorkout`'s dedicated warmup/cooldown slot, so a second `.warmup`/`.cooldown`-kind
    /// block would fall through to an ordinary work/recovery interval anyway. The Zone 2 ramp-in is
    /// marked `.work` (what it becomes on sync) rather than `.warmup`, so the model's `kind` matches
    /// what actually reaches the Watch.
    public static let tempoRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A04")!,
        name: "Tempo run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "duration", name: "Duration", unit: .minutes, defaultValue: 25 * 60, range: 15 * 60...45 * 60
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(3)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .recovery, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// Base Full-out hill sprints (MVP2-105): short, maximal uphill sprints with long, easy recoveries, run
    /// after a warmup and a Zone 2 run to the hill.
    ///
    /// The structure:
    /// 1. A fixed 5-minute Zone 1 warmup.
    /// 2. A Zone 2 run to the start of the hill, ended by the athlete (an open step, advanced
    ///    manually on the Watch).
    /// 3. `reps` times: an 8-second all-out uphill sprint (RPE 10, since no heart-rate zone is
    ///    reached in 8 seconds), then a Zone 1 recovery of `rest` seconds (walk or jog back down).
    ///    The last repetition keeps its recovery, which is the descent.
    /// 4. A Zone 2 run, again ended by the athlete, back to where the cooldown starts.
    /// 5. A fixed 5-minute Zone 1 cooldown.
    ///
    /// The two open steps count as 10 minutes each in planned duration and load, the default for
    /// a step with no goal (see ``WorkoutDurationEstimator``). Like ``tempoRun``, only the first
    /// and last single-step blocks are `.warmup`/`.cooldown`, matching what ``WorkoutKitBridge``
    /// extracts; the Zone 2 runs are `.work`. WorkoutKit has no perceived-exertion alert, so the
    /// sprint's RPE target stays in the app and isn't sent to the Watch.
    public static let baseHillSprints = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A05")!,
        name: "Base Full-out hill sprints",
        titleName: "Hill Sprints",
        sport: .running,
        venue: .outdoor(nil),
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Sprints", unit: .count, defaultValue: 6, range: 3...12),
            WorkoutTemplateParameter(
                key: "rest", name: "Rest between sprints", unit: .minutes, defaultValue: 5 * 60, range: 3 * 60...15 * 60
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .open, target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .time(.fixed(8)), target: .rpe(10)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .open, target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// Short interval run (MVP2-105): Zone 5 efforts of 30 seconds to 2 minutes with short Zone 1
    /// recoveries.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then `reps` (6-12) times a Zone 5
    /// effort of `work` seconds (30-120) and a Zone 1 recovery of `rest` seconds (60-180), then a
    /// fixed 5-minute Zone 1 cooldown. The last repetition keeps its recovery before the cooldown.
    /// As in ``tempoRun``, only the edge blocks are `.warmup`/`.cooldown`, so the Zone 2 ramp-in is
    /// `.work`, matching what ``WorkoutKitBridge`` sends to the Watch.
    public static let shortIntervalRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A06")!,
        name: "Short interval run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 8, range: 6...12),
            WorkoutTemplateParameter(key: "work", name: "Effort", unit: .minutes, defaultValue: 60, range: 30...120),
            WorkoutTemplateParameter(key: "rest", name: "Recovery", unit: .minutes, defaultValue: 90, range: 60...180),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .heartRateZone(5)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// Short interval run, track version (MVP2-105): Zone 5 efforts of 50 to 800 meters with Zone 2
    /// recoveries.
    ///
    /// The same shape as ``shortIntervalRun``, but each effort is a distance (`distance`, 50-800 m)
    /// rather than a time, and the recovery (`rest`, 60-180 s) is Zone 2, a jog, rather than Zone 1.
    /// The repetitions (`reps`) use the same 6-12 range as ``shortIntervalRun``. A distance step's
    /// planned duration comes from the athlete's pace model at Zone 5.
    public static let shortIntervalRunTrack = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A07")!,
        name: "Short interval run (track)",
        sport: .running,
        venue: .outdoor(.track),
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 8, range: 6...12),
            WorkoutTemplateParameter(key: "distance", name: "Effort", unit: .meters, defaultValue: 400, range: 50...800),
            WorkoutTemplateParameter(key: "rest", name: "Recovery", unit: .minutes, defaultValue: 90, range: 60...180),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(5)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(2)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ]
    )

    /// The maximum-heart-rate field test (MVP2-153), purpose ``WorkoutPurpose/maxHRTest``.
    ///
    /// The structure, with no parameters, since changing it changes the test:
    /// 1. A 10-minute Zone 1 warmup and a 5-minute Zone 2 ramp-in.
    /// 2. Three hard efforts of 3 minutes (RPE 9), each followed by a 1-minute Zone 1 recovery, to
    ///    bring the heart rate up while the legs are still fresh enough to keep going.
    /// 3. A final all-out effort of 3 minutes (RPE 10). The maximum is the highest heart rate held
    ///    during it.
    /// 4. A 5-minute Zone 1 cooldown.
    ///
    /// This protocol is TrainingKit's own design, not a published one: it follows the usual shape of
    /// a field test for maximum heart rate (a warmup, repeated hard efforts, then one all-out
    /// effort), but the effort and recovery lengths are our choice.
    ///
    /// Best done on a steady climb or flat, rested, and with a chest strap: a wrist sensor lags and
    /// can miss the peak. The efforts target perceived exertion, not heart-rate zones, because the
    /// zones come from the very maximum being measured. As in ``tempoRun``, only the edge blocks are
    /// `.warmup`/`.cooldown`, so the ramp-in is `.work`, matching what ``WorkoutKitBridge`` sends to
    /// the Watch.
    public static let maxHRTest = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A08")!,
        name: "Max heart rate test",
        titleName: "Max HR Test",
        sport: .running,
        parameters: [],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(10 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .time(.fixed(3 * 60)), target: .rpe(9)),
                    TemplateStep(kind: .recovery, goal: .time(.fixed(60)), target: .heartRateZone(1)),
                ],
                repetitions: .fixed(3)
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(3 * 60)), target: .rpe(10)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        purpose: .maxHRTest
    )

    /// Friel's 30-minute lactate-threshold-heart-rate field test (MVP2-153), purpose
    /// ``WorkoutPurpose/lthrTest``. The effort and the last-20-minutes average are his protocol (see
    /// TrainingPeaks, "Joe Friel's Quick Guide to Setting Zones"); the warmup and the RPE target are ours.
    ///
    /// The structure, with no parameters, since changing it changes the test:
    /// 1. A 10-minute Zone 1 warmup and a 5-minute Zone 2 ramp-in.
    /// 2. One 30-minute effort (RPE 9) as hard as can be held for the whole 30 minutes, paced evenly,
    ///    not a sprint that fades. The threshold heart rate is the average over its last 20 minutes;
    ///    the first 10 are discarded because the heart rate is still rising. It is one step so the
    ///    10-minute mark is known to whoever reads the result.
    /// 3. A 5-minute Zone 1 cooldown.
    ///
    /// Best done alone, on flat ground, with a chest strap. The effort targets perceived exertion,
    /// not heart-rate zones, since the zones are what the test sets. Like ``maxHRTest``, only the edge
    /// blocks are `.warmup`/`.cooldown`.
    public static let lthrTest = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A09")!,
        name: "Lactate threshold test (30 min)",
        titleName: "LTHR Test",
        sport: .running,
        parameters: [],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(10 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(30 * 60)), target: .rpe(9)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        purpose: .lthrTest
    )

    /// Every built-in template, in the order they should appear in a library UI.
    public static let all: [WorkoutTemplate] = [recoveryRun, easyRun, longRun, tempoRun, baseHillSprints, shortIntervalRun, shortIntervalRunTrack, maxHRTest, lthrTest]
}

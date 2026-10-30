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
        ],
        sessionType: .recovery
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
        ],
        sessionType: .easy
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
        ],
        sessionType: .long
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
        ],
        sessionType: .tempo
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
        ],
        sessionType: .hillRepeats
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
        ],
        sessionType: .interval
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
        ],
        sessionType: .interval
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
    /// `.warmup`/`.cooldown`, so the ramp-in is `.work`, matching what `WorkoutKitBridge` sends to
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

    /// Fast Finish Run (MVP2-106): an easy run that finishes faster than it started.
    ///
    /// A fixed 5-minute Zone 1 warmup, `duration` (Zone 2), then `finish` (Zone 3). The finish is
    /// about a third of the Zone 2 duration, so its default is `duration / 3` rounded to the minute
    /// (10 minutes against 30). The two are separate parameters because a template value can't be
    /// derived from another, so changing `duration` doesn't move `finish` — the athlete keeps the
    /// ratio. The run ends on the Zone 3 effort, with no cooldown.
    public static let fastFinishRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0A")!,
        name: "Fast Finish Run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "duration", name: "Zone 2 duration", unit: .minutes, defaultValue: 30 * 60, range: 15 * 60...90 * 60
            ),
            WorkoutTemplateParameter(
                key: "finish", name: "Zone 3 finish", unit: .minutes, defaultValue: 10 * 60, range: 5 * 60...30 * 60
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
                TemplateStep(kind: .work, goal: .time(.parameter("finish")), target: .heartRateZone(3)),
            ]),
        ],
        sessionType: .interval
    )

    /// Cruise Interval Runs (MVP2-106): Zone 3 intervals of 5 to 15 minutes with short Zone 1 recoveries.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then `reps` (3-6) times a Zone 3
    /// effort of `work` seconds (5-15 minutes) and a fixed 3-minute Zone 1 recovery, then a fixed
    /// 5-minute Zone 2 run and a 5-minute Zone 1 cooldown. The last repetition keeps its recovery.
    /// As in ``tempoRun``, only the edge blocks are `.warmup`/`.cooldown`, matching what
    /// `WorkoutKitBridge` sends to the Watch.
    public static let cruiseIntervalRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0B")!,
        name: "Cruise Interval Runs",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 4, range: 3...6),
            WorkoutTemplateParameter(
                key: "work", name: "Effort", unit: .minutes, defaultValue: 10 * 60, range: 5 * 60...15 * 60
            ),
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
                    TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .heartRateZone(3)),
                    TemplateStep(kind: .recovery, goal: .time(.fixed(3 * 60)), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .tempo
    )

    /// Long run with speed play, a long fartlek (MVP2-106): a long run broken up by short Zone 3 surges.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then `reps` (8-20) times 0.5 km
    /// in Zone 3 and 1.5 km in Zone 2 (a distance-based recovery, so the run is 2 km per repetition),
    /// then a fixed 5-minute Zone 1 cooldown. The last repetition keeps its Zone 2 leg.
    public static let longFartlekRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0C")!,
        name: "Long run with speed play (Long Fartlek)",
        titleName: "Long Fartlek",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 12, range: 8...20),
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
                    TemplateStep(kind: .work, goal: .distance(.fixed(500)), target: .heartRateZone(3)),
                    TemplateStep(kind: .recovery, goal: .distance(.fixed(1_500)), target: .heartRateZone(2)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .long
    )

    /// Long run with fast finish (MVP2-106): a long Zone 2 run that ends with a Zone 3 stretch.
    ///
    /// A fixed 5-minute Zone 1 warmup, `distance` (Zone 2, 12-25 km), then `finish` (Zone 3, 1-4 km).
    /// Like ``fastFinishRun`` it ends on the Zone 3 effort, with no cooldown.
    public static let longRunFastFinish = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0D")!,
        name: "Long run with fast finish",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "distance", name: "Zone 2 distance", unit: .meters, defaultValue: 16_000, range: 12_000...25_000
            ),
            WorkoutTemplateParameter(
                key: "finish", name: "Zone 3 finish", unit: .meters, defaultValue: 2_000, range: 1_000...4_000
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
                TemplateStep(kind: .work, goal: .distance(.parameter("finish")), target: .heartRateZone(3)),
            ]),
        ],
        sessionType: .long
    )

    /// Fartlek, Zone 4 (MVP2-106): short Zone 4 efforts with 2-minute Zone 1 recoveries.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then `reps` (3-12) times a Zone 4
    /// effort of `work` seconds (1-5 minutes) and a fixed 2-minute Zone 1 recovery, then a fixed
    /// 5-minute Zone 1 cooldown. The last repetition keeps its recovery. It is a separate template
    /// from ``fartlekZone5`` because a template's zone is fixed, not a parameter. Not to be confused
    /// with ``longFartlekRun``, the distance-based long run.
    public static let fartlekZone4 = fartlek(
        uuid: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0E", name: "Fartlek (Zone 4)", zone: 4
    )

    /// Fartlek, Zone 5 (MVP2-106): the same shape as ``fartlekZone4``, with Zone 5 efforts.
    public static let fartlekZone5 = fartlek(
        uuid: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A0F", name: "Fartlek (Zone 5)", zone: 5
    )

    private static func fartlek(uuid: String, name: String, zone: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(uuidString: uuid)!,
            name: name,
            titleName: "Fartlek",
            sport: .running,
            parameters: [
                WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6, range: 3...12),
                WorkoutTemplateParameter(key: "work", name: "Effort", unit: .minutes, defaultValue: 2 * 60, range: 60...5 * 60),
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
                        TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .heartRateZone(zone)),
                        TemplateStep(kind: .recovery, goal: .time(.fixed(2 * 60)), target: .heartRateZone(1)),
                    ],
                    repetitions: .parameter("reps")
                ),
                TemplateBlock(steps: [
                    TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
                ]),
            ],
            sessionType: .interval
        )
    }

    /// Hill repetition runs (MVP2-106): `reps` (6-12) uphill efforts of `work` seconds (30-90) at
    /// RPE 10, each followed by a Zone 1 recovery of `rest` seconds (90-150).
    ///
    /// A fixed 5-minute Zone 1 warmup, then a Zone 2 run to the hill ended by the athlete (an open
    /// step, counted as 10 minutes in planned duration and load), the repetitions, then a fixed
    /// 5-minute Zone 1 cooldown. Unlike ``baseHillSprints`` there is no second open run: the last
    /// recovery is the descent, and the cooldown follows. The effort's RPE target stays in the app,
    /// since WorkoutKit has no perceived-exertion alert.
    public static let hillRepetitionRun = hillRepetitions(
        uuid: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A10", name: "Hill Repetition Runs", titleName: "Hill Repeats", effortRPE: 10
    )

    private static func hillRepetitions(uuid: String, name: String, titleName: String, effortRPE: Int) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(uuidString: uuid)!,
            name: name,
            titleName: titleName,
            sport: .running,
            venue: .outdoor(nil),
            parameters: [
                WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 8, range: 6...12),
                WorkoutTemplateParameter(key: "work", name: "Uphill effort", unit: .minutes, defaultValue: 60, range: 30...90),
                WorkoutTemplateParameter(key: "rest", name: "Recovery", unit: .minutes, defaultValue: 120, range: 90...150),
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
                        TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .rpe(effortRPE)),
                        TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                    ],
                    repetitions: .parameter("reps")
                ),
                TemplateBlock(steps: [
                    TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
                ]),
            ],
            sessionType: .hillRepeats
        )
    }

    /// Long interval runs (MVP2-106): Zone 4 efforts of 3 to 5 minutes with Zone 1 recoveries of 2 to 4 minutes.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then `reps` (3-8) times a Zone 4
    /// effort of `work` seconds (3-5 minutes) and a Zone 1 recovery of `rest` seconds (2-4 minutes),
    /// then a fixed 5-minute Zone 1 cooldown. The last repetition keeps its recovery. Like
    /// ``shortIntervalRun``, only the edge blocks are `.warmup`/`.cooldown`.
    public static let longIntervalRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A11")!,
        name: "Long Interval Runs",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 5, range: 3...8),
            WorkoutTemplateParameter(
                key: "work", name: "Effort", unit: .minutes, defaultValue: 4 * 60, range: 3 * 60...5 * 60
            ),
            WorkoutTemplateParameter(
                key: "rest", name: "Recovery", unit: .minutes, defaultValue: 3 * 60, range: 2 * 60...4 * 60
            ),
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
                    TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .heartRateZone(4)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .interval
    )

    /// Mixed interval runs (MVP2-106): a ladder of Zone 5 and Zone 4 efforts around a 10-minute Zone 3 block.
    ///
    /// A fixed 5-minute Zone 1 warmup and 5-minute Zone 2 ramp-in, then, mirrored around the Zone 3
    /// block:
    /// 1. `reps` (1-3) times a Zone 5 effort of `hard` seconds (30-120) and a 3-minute Zone 1 recovery.
    /// 2. `reps` times a Zone 4 effort of `moderate` seconds (90-360) and a 2-minute Zone 1 recovery.
    /// 3. A fixed 10-minute Zone 3 run.
    /// 4. The Zone 4 block again.
    /// 5. The Zone 5 block again.
    /// 6. A fixed 5-minute Zone 1 cooldown.
    ///
    /// The mirrored blocks share their `reps`, `hard` and `moderate` parameters, so the workout stays
    /// symmetric. The last repetition of each block keeps its recovery.
    public static let mixedIntervalRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A12")!,
        name: "Mixed Interval Runs",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 2, range: 1...3),
            WorkoutTemplateParameter(key: "hard", name: "Zone 5 effort", unit: .minutes, defaultValue: 60, range: 30...120),
            WorkoutTemplateParameter(
                key: "moderate", name: "Zone 4 effort", unit: .minutes, defaultValue: 3 * 60, range: 90...6 * 60
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
            ]),
            zone5Block,
            zone4Block,
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(10 * 60)), target: .heartRateZone(3)),
            ]),
            zone4Block,
            zone5Block,
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .interval
    )

    private static let zone5Block = TemplateBlock(
        steps: [
            TemplateStep(kind: .work, goal: .time(.parameter("hard")), target: .heartRateZone(5)),
            TemplateStep(kind: .recovery, goal: .time(.fixed(3 * 60)), target: .heartRateZone(1)),
        ],
        repetitions: .parameter("reps")
    )

    private static let zone4Block = TemplateBlock(
        steps: [
            TemplateStep(kind: .work, goal: .time(.parameter("moderate")), target: .heartRateZone(4)),
            TemplateStep(kind: .recovery, goal: .time(.fixed(2 * 60)), target: .heartRateZone(1)),
        ],
        repetitions: .parameter("reps")
    )

    /// Sarcomere runs (MVP2-106): ``hillRepetitionRun`` run downhill, eccentric repetitions that
    /// build muscle strength and resistance to the damage of downhill running.
    ///
    /// The same structure and parameters as ``hillRepetitionRun``: a 5-minute Zone 1 warmup, an open
    /// Zone 2 run, here to the top of the hill, `reps` (6-12) times a fast downhill effort of `work`
    /// seconds (30-90) and a Zone 1 recovery of `rest` seconds (90-150), the walk or jog back up the
    /// hill, and a 5-minute Zone 1 cooldown. The downhill effort is RPE 8, fast but controlled, not the all-out
    /// RPE 10 of the uphill version: a flat-out descent risks a fall, and the stimulus is the
    /// eccentric load, not the effort. The downhill itself isn't modelled, so the athlete picks the
    /// slope. The RPE target stays in the app, since WorkoutKit has no perceived-exertion alert.
    public static let sarcomereRun = hillRepetitions(
        uuid: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A13", name: "Sarcomere Runs", titleName: "Downhill Repeats", effortRPE: 8
    )

    // MARK: Run Elite workouts

    // The structures below come from the user's Run Elite notes (`notes/run-elite.md`). Their zones follow the
    // user's own mapping of the book's percentages of race speed to heart-rate zones (86-94 % Z2, 95-99 % Z3
    // lower half, 106-114 % Z4, 3-5K pace Z4-5); the template cannot say which percentage a zone stands for,
    // so the phase's race-target fraction does that (``StepTargetResolver``).

    /// Alternation run (Run Elite, Specific): a long run that alternates continuously between faster and
    /// slower than race pace.
    ///
    /// A fixed 5-minute Zone 1 warmup, an easy Zone 2 run of `build` (10-20 km) metres, then `reps`
    /// (4-10) times 1 km in Zone 4 (about 106 % of race speed) and 1 km in Zone 3 (about 95 %, the
    /// recovery that is almost race pace), then a fixed 5-minute Zone 1 cooldown. The notes' example is 15 km
    /// of build and 15 km of alternation (7.5 pairs); the default of 8 pairs rounds up. It wants 1 day free
    /// before it and 3 after (``RecoveryDays``): at least one very easy day before and several recovery days after. The first half
    /// "builds" in speed, which a single Zone 2 step cannot show; the athlete eases into it.
    public static let alternationRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A14")!,
        name: "Alternation Run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "build", name: "Easy build distance", unit: .meters, defaultValue: 15_000, range: 10_000...20_000
            ),
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 8, range: 4...10),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .distance(.parameter("build")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.fixed(1_000)), target: .heartRateZone(4)),
                    TemplateStep(kind: .recovery, goal: .distance(.fixed(1_000)), target: .heartRateZone(3)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .long,
        recoveryDays: RecoveryDays(before: 1, after: 3)
    )

    /// Muscular endurance repeats (Run Elite, Support endurance quality): repeats at 86-94 % of race speed
    /// with short recoveries.
    ///
    /// A fixed 5-minute Zone 1 warmup, then `reps` (2-30) times a Zone 2 effort of `distance` (400 m to
    /// 6.4 km) and a Zone 1 recovery of `rest` seconds (20-60), then a fixed 5-minute Zone 1 cooldown.
    /// The notes' progression is 6 x 1 mile, 2 x 4 miles and 30 x 400 m with recoveries of 20-30 s; the
    /// default is the mile repeats. A single continuous tempo is not offered, since the notes add
    /// distance with intervals.
    public static let enduranceRepeats = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A15")!,
        name: "Muscular Endurance Repeats",
        titleName: "Endurance Repeats",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6, range: 2...30),
            WorkoutTemplateParameter(
                key: "distance", name: "Effort distance", unit: .meters, defaultValue: 1_600, range: 400...6_400
            ),
            WorkoutTemplateParameter(key: "rest", name: "Recovery", unit: .minutes, defaultValue: 30, range: 20...60),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(2)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .interval
    )

    /// Speed endurance repeats (Run Elite, Support fast quality): repeats at 106-114 % of race speed with a
    /// jog recovery of the same kind of distance.
    ///
    /// A fixed 5-minute Zone 1 warmup, then `reps` (6-30) times a Zone 4 effort of `distance` (200 m to
    /// 1 km) and a Zone 1 recovery of `rest` metres (100 m to 1 km), then a fixed 5-minute Zone 1
    /// cooldown. The notes' progression is 20-24 x 200 m with 200 m recovery and 6 x 400 m blocks; the
    /// default is 20 x 200 m with 200 m. The 3-mile tempo of its last step is ``tempoRun``.
    public static let speedEnduranceRepeats = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A16")!,
        name: "Speed Endurance Repeats",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 20, range: 6...30),
            WorkoutTemplateParameter(
                key: "distance", name: "Effort distance", unit: .meters, defaultValue: 200, range: 200...1_000
            ),
            WorkoutTemplateParameter(
                key: "rest", name: "Recovery distance", unit: .meters, defaultValue: 200, range: 100...1_000
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(4)),
                    TemplateStep(kind: .recovery, goal: .distance(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .interval
    )

    /// Long run with endurance intervals (Run Elite, Support): a long run made of blocks at 86-94 % of race
    /// speed, e.g. 3 x 5 km at 94 %.
    ///
    /// A fixed 5-minute Zone 1 warmup, an easy Zone 2 run of `easy` metres, `reps` (2-4) times a Zone 2
    /// effort of `distance` (3-8 km) and a Zone 1 recovery of `rest` seconds (1-5 minutes), another easy
    /// Zone 2 run of `easy` metres, and a fixed 5-minute Zone 1 cooldown. With the defaults the
    /// intervals and the two easy runs are 20 km, the notes' example. The notes give no recovery length;
    /// 3 minutes is this template's.
    public static let longRunEnduranceIntervals = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A17")!,
        name: "Long run with endurance intervals",
        titleName: "Long Run Intervals",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 3, range: 2...4),
            WorkoutTemplateParameter(
                key: "distance", name: "Effort distance", unit: .meters, defaultValue: 5_000, range: 3_000...8_000
            ),
            WorkoutTemplateParameter(
                key: "rest", name: "Recovery", unit: .minutes, defaultValue: 3 * 60, range: 60...5 * 60
            ),
            WorkoutTemplateParameter(
                key: "easy", name: "Easy distance before and after", unit: .meters, defaultValue: 2_500, range: 1_000...8_000
            ),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .distance(.parameter("easy")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(2)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .distance(.parameter("easy")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .long
    )

    /// Long run with speed intervals (Run Elite, Support fast quality): an easy long run plus repeats at
    /// 106-114 % of race speed, e.g. 20 km easy plus 6 x 1000 m.
    ///
    /// A fixed 5-minute Zone 1 warmup, an easy Zone 2 run of `easy` metres (10-25 km), then `reps` (4-10)
    /// times a Zone 4 effort of `distance` (400 m to 2 km) and a Zone 1 recovery of `rest` seconds
    /// (1-5 minutes), and a fixed 5-minute Zone 1 cooldown. The notes give neither the order nor the
    /// recovery length; easy first and 2 minutes are this template's.
    public static let longRunSpeedIntervals = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A18")!,
        name: "Long run with speed intervals",
        titleName: "Long Run Speed",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(
                key: "easy", name: "Easy distance", unit: .meters, defaultValue: 20_000, range: 10_000...25_000
            ),
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6, range: 4...10),
            WorkoutTemplateParameter(
                key: "distance", name: "Effort distance", unit: .meters, defaultValue: 1_000, range: 400...2_000
            ),
            WorkoutTemplateParameter(key: "rest", name: "Recovery", unit: .minutes, defaultValue: 2 * 60, range: 60...5 * 60),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .distance(.parameter("easy")), target: .heartRateZone(2)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.parameter("distance")), target: .heartRateZone(4)),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("rest")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .long
    )

    /// Glycogen store run (Run Elite, race eve): a short run 24-36 hours before the race that ends with one
    /// 90-second interval at 3-5K pace; the carbohydrate meal that follows is the point of it.
    ///
    /// A Zone 1 warmup of `warmup` metres (1-3 km), `strides` (3-6) times a 100 m stride with no target
    /// ("quick and relaxed") and a Zone 1 jog of 100 m, then one fixed 90-second Zone 5 interval. There is
    /// no cooldown. The notes do not say how the strides are recovered; the 100 m jog is this template's.
    /// The meal (400-600 kcal of carbohydrate straight after) is not part of the workout.
    public static let glycogenStoreRun = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A19")!,
        name: "Glycogen Store Run",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "warmup", name: "Warmup distance", unit: .meters, defaultValue: 2_000, range: 1_000...3_000),
            WorkoutTemplateParameter(key: "strides", name: "Strides", unit: .count, defaultValue: 4, range: 3...6),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .distance(.parameter("warmup")), target: .heartRateZone(1)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .distance(.fixed(100))),
                    TemplateStep(kind: .recovery, goal: .distance(.fixed(100)), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("strides")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(90)), target: .heartRateZone(5)),
            ]),
        ],
        sessionType: .interval
    )

    /// Repeats at the intensity of the phase (MVP5-153): the key interval session for any race distance.
    ///
    /// A fixed 10-minute Zone 1 warmup, then `reps` (2-20) times a `work` effort (30 s to 20 minutes) at the
    /// intensity of the plan's phase (``IntensityTarget/phaseIntensity``) and a `recovery` (30-240 s) in Zone 1,
    /// then a fixed 5-minute Zone 1 cooldown. The effort fixes no zone: in a plan it is the race pace divided by the
    /// phase's fraction, whatever zone that is for the athlete, so the same template gives 1000 m repeats at 5k pace,
    /// 2 km repeats at 10k pace and 5 km blocks at half-marathon pace. Outside a plan the effort reads as a
    /// moderate one. Tagged interval.
    public static let intensityRepeats = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A1A")!,
        name: "Repeats at phase intensity",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 5, range: 2...20),
            WorkoutTemplateParameter(key: "work", name: "Effort", unit: .minutes, defaultValue: 4 * 60, range: 30...20 * 60),
            WorkoutTemplateParameter(key: "recovery", name: "Recovery", unit: .minutes, defaultValue: 90, range: 30...240),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(10 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .phaseIntensity),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("recovery")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .interval
    )

    /// Steady blocks at the intensity of the phase (MVP5-153): threshold or tempo work for any race distance.
    ///
    /// A fixed 10-minute Zone 1 warmup, then `reps` (1-4) times a `work` block (10-60 minutes) at the intensity of the
    /// plan's phase (``IntensityTarget/phaseIntensity``) and a `recovery` (1-5 minutes) in Zone 1, then a fixed
    /// 5-minute Zone 1 cooldown. As in ``intensityRepeats`` the effort fixes no zone: 92 % of a 5k pace is a threshold
    /// effort, 105 % of a half-marathon pace is one too. Tagged tempo.
    public static let intensityBlocks = WorkoutTemplate(
        id: UUID(uuidString: "8F5D6E4E-6E0E-4B8B-9C1A-9E6F9F1C1A1B")!,
        name: "Steady blocks at phase intensity",
        sport: .running,
        parameters: [
            WorkoutTemplateParameter(key: "reps", name: "Blocks", unit: .count, defaultValue: 2, range: 1...4),
            WorkoutTemplateParameter(key: "work", name: "Block length", unit: .minutes, defaultValue: 20 * 60, range: 10 * 60...60 * 60),
            WorkoutTemplateParameter(key: "recovery", name: "Recovery", unit: .minutes, defaultValue: 2 * 60, range: 60...5 * 60),
        ],
        blocks: [
            TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(10 * 60)), target: .heartRateZone(1)),
            ]),
            TemplateBlock(
                steps: [
                    TemplateStep(kind: .work, goal: .time(.parameter("work")), target: .phaseIntensity),
                    TemplateStep(kind: .recovery, goal: .time(.parameter("recovery")), target: .heartRateZone(1)),
                ],
                repetitions: .parameter("reps")
            ),
            TemplateBlock(steps: [
                TemplateStep(kind: .cooldown, goal: .time(.fixed(5 * 60)), target: .heartRateZone(1)),
            ]),
        ],
        sessionType: .tempo
    )

    /// Every built-in template, in the order they should appear in a library UI.
    public static let all: [WorkoutTemplate] = [recoveryRun, easyRun, longRun, tempoRun, baseHillSprints, shortIntervalRun, shortIntervalRunTrack, maxHRTest, lthrTest, fastFinishRun, cruiseIntervalRun, longFartlekRun, longRunFastFinish, fartlekZone4, fartlekZone5, hillRepetitionRun, longIntervalRun, mixedIntervalRun, sarcomereRun, alternationRun, enduranceRepeats, speedEnduranceRepeats, longRunEnduranceIntervals, longRunSpeedIntervals, glycogenStoreRun, intensityRepeats, intensityBlocks]
}

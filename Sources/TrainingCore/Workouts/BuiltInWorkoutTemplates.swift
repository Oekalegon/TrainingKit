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
        sport: .running,
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

    /// Every built-in template, in the order they should appear in a library UI.
    public static let all: [WorkoutTemplate] = [recoveryRun, easyRun, longRun, tempoRun, baseHillSprints, shortIntervalRun, shortIntervalRunTrack]
}

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
                TemplateStep(kind: .warmup, goal: .time(.fixed(5 * 60)), target: .heartRateZone(2)),
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

    /// Every built-in template, in the order they should appear in a library UI.
    public static let all: [WorkoutTemplate] = [recoveryRun, easyRun, longRun, tempoRun]
}

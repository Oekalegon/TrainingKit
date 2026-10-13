import Foundation
import Testing
@testable import TrainingCore

@Suite("BuiltInWorkoutTemplates")
struct BuiltInWorkoutTemplatesTests {
    @Test("recovery run instantiates as a single Zone 1 block at the requested duration")
    func recoveryRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.recoveryRun.instantiate(values: ["duration": 25 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(25 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("easy run instantiates with fixed warmup/cooldown and a variable Zone 2 main block")
    func easyRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(values: ["duration": 40 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(40 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("long run instantiates with fixed warmup/cooldown and a variable Zone 2 main distance")
    func longRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.longRun.instantiate(values: ["distance": 28_000])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(28_000), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("tempo run instantiates with only the true edges as warmup/cooldown, matching what WorkoutKitBridge extracts")
    func tempoRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.tempoRun.instantiate(values: ["duration": 20 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(20 * 60), target: .heartRateZone(3))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .recovery, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("base full-out hill sprints: warmup, open Zone 2 run, N × (8 s all-out, Zone 1 rest), open Zone 2 run, cooldown")
    func baseHillSprintsInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.baseHillSprints.instantiate(values: ["reps": 8, "rest": 4 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(8), target: .rpe(10)),
                    WorkoutStep(kind: .recovery, goal: .time(4 * 60), target: .heartRateZone(1)),
                ],
                repetitions: 8
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("base full-out hill sprints default to 6 sprints with 5 minutes' rest, and offer 3–12 sprints and 3–15 minutes' rest")
    func baseHillSprintsDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.baseHillSprints
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 6)
        #expect(workout.blocks[2].steps[1].goal == .time(300))
        let reps = try #require(template.parameters.first { $0.key == "reps" })
        let rest = try #require(template.parameters.first { $0.key == "rest" })
        #expect(reps.range == 3...12)
        #expect(rest.range == 180...900)
    }

    @Test("short interval run: warmup, Zone 2 ramp-in, N × (Zone 5 effort, Zone 1 recovery), cooldown")
    func shortIntervalRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate(values: ["reps": 10, "work": 45, "rest": 120])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(45), target: .heartRateZone(5)),
                    WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(1)),
                ],
                repetitions: 10
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("short interval run defaults to 8 × 1 min with 90 s recovery, and offers 6–12 reps, 30–120 s efforts, 60–180 s recoveries")
    func shortIntervalRunDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.shortIntervalRun
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 8)
        #expect(workout.blocks[2].steps.map(\.goal) == [.time(60), .time(90)])
        func range(_ key: String) throws -> ClosedRange<Double>? { try #require(template.parameters.first { $0.key == key }).range }
        #expect(try range("reps") == 6...12)
        #expect(try range("work") == 30...120)
        #expect(try range("rest") == 60...180)
    }

    @Test("short interval run (track): N × (Zone 5 distance, Zone 2 recovery) between the warmup and cooldown")
    func shortIntervalRunTrackInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRunTrack.instantiate(values: ["reps": 6, "distance": 200, "rest": 75])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .distance(200), target: .heartRateZone(5)),
                    WorkoutStep(kind: .recovery, goal: .time(75), target: .heartRateZone(2)),
                ],
                repetitions: 6
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("short interval run (track) defaults to 8 × 400 m with 90 s recovery, and offers 6–12 reps, 50–800 m efforts, 60–180 s recoveries")
    func shortIntervalRunTrackDefaultsAndRanges() throws {
        let template = BuiltInWorkoutTemplates.shortIntervalRunTrack
        let workout = try template.instantiate()

        #expect(workout.blocks[2].repetitions == 8)
        #expect(workout.blocks[2].steps.map(\.goal) == [.distance(400), .time(90)])
        func range(_ key: String) throws -> ClosedRange<Double>? { try #require(template.parameters.first { $0.key == key }).range }
        #expect(try range("reps") == 6...12)
        #expect(try range("distance") == 50...800)
        #expect(try range("rest") == 60...180)
    }

    @Test("the interval templates plan a duration from their steps, counting each open step as 10 minutes")
    func intervalTemplatesPlannedDuration() throws {
        let athlete = AthleteProfile.fixture()
        let estimator = WorkoutDurationEstimator()

        let hills = try BuiltInWorkoutTemplates.baseHillSprints.instantiate()
        // 5 min warmup + open run + 6 × (8 s sprint + 5 min rest) + open run + 5 min cooldown.
        let hillRepetition: TimeInterval = 8 + 300
        let expectedHills: TimeInterval = 300 + 600 + 6 * hillRepetition + 600 + 300
        #expect(estimator.duration(for: hills, athlete: athlete) == expectedHills)

        let short = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()
        // 5 + 5 min, 8 × (60 s + 90 s), 5 min cooldown.
        let shortRepetition: TimeInterval = 60 + 90
        let expectedShort: TimeInterval = 300 + 300 + 8 * shortRepetition + 300
        #expect(estimator.duration(for: short, athlete: athlete) == expectedShort)
    }

    @Test("fast finish run: Zone 1 warmup, Zone 2 run, then a Zone 3 finish of about a third of it")
    func fastFinishRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.fastFinishRun.instantiate()

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(30 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(10 * 60), target: .heartRateZone(3))]),
        ])
    }

    @Test("cruise interval runs: N × (Zone 3 effort, 3 min Zone 1) between Zone 1/2 ramps and a Zone 2/1 finish")
    func cruiseIntervalRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.cruiseIntervalRun.instantiate(values: ["reps": 5, "work": 8 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(8 * 60), target: .heartRateZone(3)),
                    WorkoutStep(kind: .recovery, goal: .time(3 * 60), target: .heartRateZone(1)),
                ],
                repetitions: 5
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("fartlek long run: N × (0.5 km Zone 3, 1.5 km Zone 2) between a Zone 1/2 start and a Zone 1 cooldown")
    func longFartlekRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.longFartlekRun.instantiate(values: ["reps": 10])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .distance(500), target: .heartRateZone(3)),
                    WorkoutStep(kind: .recovery, goal: .distance(1_500), target: .heartRateZone(2)),
                ],
                repetitions: 10
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("long run with fast finish: Zone 1 warmup, Zone 2 distance, then a Zone 3 distance finish")
    func longRunFastFinishInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.longRunFastFinish.instantiate(values: ["distance": 20_000, "finish": 3_000])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(20_000), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(3_000), target: .heartRateZone(3))]),
        ])
    }

    @Test("fartlek: N × (Zone 4 or 5 effort, 2 min Zone 1) between Zone 1/2 ramps and a Zone 1 cooldown")
    func fartlekInstantiates() throws {
        for (template, zone) in [(BuiltInWorkoutTemplates.fartlekZone4, 4), (BuiltInWorkoutTemplates.fartlekZone5, 5)] {
            let workout = try template.instantiate(values: ["reps": 4, "work": 3 * 60.0])

            #expect(workout.blocks == [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
                WorkoutBlock(
                    steps: [
                        WorkoutStep(kind: .work, goal: .time(3 * 60), target: .heartRateZone(zone)),
                        WorkoutStep(kind: .recovery, goal: .time(2 * 60), target: .heartRateZone(1)),
                    ],
                    repetitions: 4
                ),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
            ])
        }
    }

    @Test("hill repetition runs: warmup, open Zone 2 run, N × (RPE 10 uphill, Zone 1 recovery), cooldown")
    func hillRepetitionRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.hillRepetitionRun.instantiate(values: ["reps": 10, "work": 45, "rest": 100])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(45), target: .rpe(10)),
                    WorkoutStep(kind: .recovery, goal: .time(100), target: .heartRateZone(1)),
                ],
                repetitions: 10
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("long interval runs: N × (Zone 4 effort, Zone 1 recovery) between Zone 1/2 ramps and a Zone 1 cooldown")
    func longIntervalRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.longIntervalRun.instantiate(values: ["reps": 6, "work": 3 * 60.0, "rest": 2 * 60.0])

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(3 * 60), target: .heartRateZone(4)),
                    WorkoutStep(kind: .recovery, goal: .time(2 * 60), target: .heartRateZone(1)),
                ],
                repetitions: 6
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("mixed interval runs: Zone 5 and Zone 4 blocks mirrored around a 10 min Zone 3 run")
    func mixedIntervalRunInstantiates() throws {
        let workout = try BuiltInWorkoutTemplates.mixedIntervalRun.instantiate(values: ["reps": 2, "hard": 90, "moderate": 4 * 60.0])
        let zone5 = WorkoutBlock(
            steps: [
                WorkoutStep(kind: .work, goal: .time(90), target: .heartRateZone(5)),
                WorkoutStep(kind: .recovery, goal: .time(3 * 60), target: .heartRateZone(1)),
            ],
            repetitions: 2
        )
        let zone4 = WorkoutBlock(
            steps: [
                WorkoutStep(kind: .work, goal: .time(4 * 60), target: .heartRateZone(4)),
                WorkoutStep(kind: .recovery, goal: .time(2 * 60), target: .heartRateZone(1)),
            ],
            repetitions: 2
        )

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5 * 60), target: .heartRateZone(2))]),
            zone5,
            zone4,
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(10 * 60), target: .heartRateZone(3))]),
            zone4,
            zone5,
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("sarcomere runs match the hill repetition runs, except the downhill effort is RPE 8 rather than RPE 10")
    func sarcomereRunMatchesHillRepetitionRun() throws {
        let sarcomere = BuiltInWorkoutTemplates.sarcomereRun
        let hill = BuiltInWorkoutTemplates.hillRepetitionRun

        #expect(sarcomere.parameters == hill.parameters)
        #expect(sarcomere.id != hill.id)

        let workout = try sarcomere.instantiate(values: ["reps": 10, "work": 45, "rest": 100])
        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(5 * 60), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(45), target: .rpe(8)),
                    WorkoutStep(kind: .recovery, goal: .time(100), target: .heartRateZone(1)),
                ],
                repetitions: 10
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(5 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("every built-in template has a positive estimated load with its default parameters")
    func builtInsHavePositiveLoad() throws {
        let athlete = AthleteProfile.fixture()

        for template in BuiltInWorkoutTemplates.all {
            let load = try template.expectedLoad(estimator: TRIMPPlanEstimator(), athlete: athlete)
            #expect(load.value > 0, "\(template.name)")
        }
    }

    @Test("built-in templates have distinct, stable ids")
    func builtInsHaveDistinctIDs() {
        let ids = Set(BuiltInWorkoutTemplates.all.map(\.id))

        #expect(ids.count == BuiltInWorkoutTemplates.all.count)
    }
}

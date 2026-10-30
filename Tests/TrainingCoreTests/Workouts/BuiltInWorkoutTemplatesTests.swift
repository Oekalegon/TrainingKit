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
        #expect(!sarcomere.blocks.flatMap(\.steps).contains { $0.target == .rpe(10) })
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

    @Test("the MVP2-106 hill templates plan a duration counting their open step as 10 minutes")
    func hillTemplatesPlannedDuration() throws {
        let athlete = AthleteProfile.fixture()
        let estimator = WorkoutDurationEstimator()
        // 5 min warmup + open run + 8 × (60 s effort + 120 s recovery) + 5 min cooldown.
        let expected: TimeInterval = 300 + 600 + 8 * (60 + 120) + 300

        for template in [BuiltInWorkoutTemplates.hillRepetitionRun, BuiltInWorkoutTemplates.sarcomereRun] {
            let workout = try template.instantiate()
            #expect(estimator.duration(for: workout, athlete: athlete) == expected, "\(template.name)")
        }
    }

    @Test("the MVP2-106 templates name generated workouts by their short title")
    func mvp2106DefaultTitles() {
        #expect(BuiltInWorkoutTemplates.fartlekZone4.defaultTitle().contains("Fartlek"))
        #expect(BuiltInWorkoutTemplates.fartlekZone5.defaultTitle().contains("Fartlek"))
        #expect(BuiltInWorkoutTemplates.hillRepetitionRun.defaultTitle().contains("Hill Repeats"))
        #expect(BuiltInWorkoutTemplates.sarcomereRun.defaultTitle().contains("Downhill Repeats"))
        #expect(BuiltInWorkoutTemplates.longFartlekRun.defaultTitle().contains("Long Fartlek"))
    }

    @Test("the MVP2-106 templates offer the ticket's parameter ranges, with defaults inside them")
    func mvp2106ParameterRanges() throws {
        let expected: [(WorkoutTemplate, [String: ClosedRange<Double>])] = [
            (BuiltInWorkoutTemplates.fastFinishRun, ["duration": 900...5_400, "finish": 300...1_800]),
            (BuiltInWorkoutTemplates.longRunFastFinish, ["distance": 12_000...25_000, "finish": 1_000...4_000]),
            (BuiltInWorkoutTemplates.cruiseIntervalRun, ["reps": 3...6, "work": 300...900]),
            (BuiltInWorkoutTemplates.longIntervalRun, ["reps": 3...8, "work": 180...300, "rest": 120...240]),
            (BuiltInWorkoutTemplates.mixedIntervalRun, ["reps": 1...3, "hard": 30...120, "moderate": 90...360]),
            (BuiltInWorkoutTemplates.longFartlekRun, ["reps": 8...20]),
            (BuiltInWorkoutTemplates.fartlekZone4, ["reps": 3...12, "work": 60...300]),
            (BuiltInWorkoutTemplates.fartlekZone5, ["reps": 3...12, "work": 60...300]),
            (BuiltInWorkoutTemplates.hillRepetitionRun, ["reps": 6...12, "work": 30...90, "rest": 90...150]),
            (BuiltInWorkoutTemplates.sarcomereRun, ["reps": 6...12, "work": 30...90, "rest": 90...150]),
        ]

        for (template, ranges) in expected {
            #expect(Set(template.parameters.map(\.key)) == Set(ranges.keys), "\(template.name)")
            for parameter in template.parameters {
                #expect(parameter.range == ranges[parameter.key], "\(template.name) \(parameter.key)")
                #expect(parameter.range?.contains(parameter.defaultValue) == true, "\(template.name) \(parameter.key) default")
            }
        }
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

    @Test("the Run Elite templates offer the notes' ranges, with defaults inside them")
    func runEliteParameterRanges() throws {
        let expected: [(WorkoutTemplate, [String: ClosedRange<Double>])] = [
            (BuiltInWorkoutTemplates.alternationRun, ["build": 10_000...20_000, "reps": 4...10]),
            (BuiltInWorkoutTemplates.enduranceRepeats, ["reps": 2...30, "distance": 400...6_400, "rest": 20...60]),
            (BuiltInWorkoutTemplates.speedEnduranceRepeats, ["reps": 6...30, "distance": 200...1_000, "rest": 100...1_000]),
            (BuiltInWorkoutTemplates.longRunEnduranceIntervals, ["reps": 2...4, "distance": 3_000...8_000, "rest": 60...300, "easy": 1_000...8_000]),
            (BuiltInWorkoutTemplates.longRunSpeedIntervals, ["easy": 10_000...25_000, "reps": 4...10, "distance": 400...2_000, "rest": 60...300]),
            (BuiltInWorkoutTemplates.glycogenStoreRun, ["warmup": 1_000...3_000, "strides": 3...6]),
        ]

        for (template, ranges) in expected {
            #expect(Set(template.parameters.map(\.key)) == Set(ranges.keys), "\(template.name)")
            for parameter in template.parameters {
                #expect(parameter.range == ranges[parameter.key], "\(template.name) \(parameter.key)")
                #expect(parameter.range?.contains(parameter.defaultValue) == true, "\(template.name) \(parameter.key)")
            }
            _ = try template.instantiate()
        }
    }

    @Test("the notes' example sessions come out at their stated size with the defaults")
    func runEliteExamples() throws {
        // 15 km build, then 8 pairs of 1 km.
        let alternation = try BuiltInWorkoutTemplates.alternationRun.instantiate()
        let alternationDistance = alternation.blocks.flatMap { block in
            Array(repeating: block.steps, count: block.repetitions).flatMap { $0 }
        }.reduce(0.0) { total, step in
            if case .distance(let meters) = step.goal { total + meters } else { total }
        }
        #expect(alternationDistance == 15_000 + 16_000)

        // 20 km: 2 x 2.5 km easy and 3 x 5 km.
        let longRun = try BuiltInWorkoutTemplates.longRunEnduranceIntervals.instantiate()
        let longRunDistance = longRun.blocks.flatMap { block in
            Array(repeating: block.steps, count: block.repetitions).flatMap { $0 }
        }.reduce(0.0) { total, step in
            if case .distance(let meters) = step.goal { total + meters } else { total }
        }
        #expect(longRunDistance == 20_000)

        // One 90 s interval at the end, in Zone 5.
        let store = try BuiltInWorkoutTemplates.glycogenStoreRun.instantiate()
        let last = try #require(store.blocks.last?.steps.last)
        #expect(last.goal == .time(90) && last.target == .heartRateZone(5))
    }

    // MARK: Phase intensity (MVP5-153)

    @Test("the phase-intensity templates have a hard effort of any length at the phase's intensity, and no fixed zone for it")
    func phaseIntensityTemplates() throws {
        let athlete = AthleteProfile.fixture()
        let repeats = try BuiltInWorkoutTemplates.intensityRepeats.analysis(athlete: athlete)
        #expect(repeats.workLength == 30...1200)
        #expect(repeats.workCount.lowerBound == 2 && repeats.workCount.upperBound == 20)
        let blocks = try BuiltInWorkoutTemplates.intensityBlocks.analysis(athlete: athlete)
        #expect(blocks.workLength == 600...3600)
        #expect(BuiltInWorkoutTemplates.intensityRepeats.sessionType == .interval && BuiltInWorkoutTemplates.intensityBlocks.sessionType == .tempo)
        for template in [BuiltInWorkoutTemplates.intensityRepeats, BuiltInWorkoutTemplates.intensityBlocks] {
            let workout = try template.instantiate()
            let work = workout.blocks.flatMap(\.steps).filter { $0.kind == .work }
            #expect(work.count == 1 && work[0].target == .phaseIntensity)
        }
    }
}

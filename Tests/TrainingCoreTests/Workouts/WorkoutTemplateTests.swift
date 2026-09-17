import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutTemplate")
struct WorkoutTemplateTests {
    @Test("instantiate resolves a parameter to the supplied value")
    func resolvesSuppliedValue() throws {
        let template = WorkoutTemplate(
            name: "Recovery run",
            sport: .running,
            parameters: [WorkoutTemplateParameter(key: "duration", name: "Duration", unit: .minutes, defaultValue: 20 * 60)],
            blocks: [
                TemplateBlock(steps: [
                    TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(1)),
                ]),
            ]
        )

        let workout = try template.instantiate(values: ["duration": 30 * 60.0])

        #expect(workout.name == "Recovery run")
        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(30 * 60), target: .heartRateZone(1))]),
        ])
    }

    @Test("instantiate falls back to the parameter's default when no value is supplied")
    func fallsBackToDefault() throws {
        let template = WorkoutTemplate(
            name: "Recovery run",
            sport: .running,
            parameters: [WorkoutTemplateParameter(key: "duration", name: "Duration", unit: .minutes, defaultValue: 20 * 60)],
            blocks: [
                TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("duration")))]),
            ]
        )

        let workout = try template.instantiate()

        #expect(workout.blocks == [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(20 * 60))])])
    }

    @Test("instantiate resolves fixed values and a parameterized repetition count")
    func resolvesFixedValuesAndRepetitions() throws {
        let template = WorkoutTemplate(
            name: "Intervals",
            sport: .running,
            parameters: [WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6)],
            blocks: [
                TemplateBlock(
                    steps: [TemplateStep(kind: .work, goal: .distance(.fixed(400)), target: .heartRateZone(4))],
                    repetitions: .parameter("reps")
                ),
            ]
        )

        let workout = try template.instantiate(values: ["reps": 8])

        #expect(workout.blocks == [
            WorkoutBlock(
                steps: [WorkoutStep(kind: .work, goal: .distance(400), target: .heartRateZone(4))],
                repetitions: 8
            ),
        ])
    }

    @Test("instantiate rounds a fractional resolved repetition count instead of truncating it")
    func roundsFractionalRepetitions() throws {
        let template = WorkoutTemplate(
            name: "Intervals",
            sport: .running,
            parameters: [WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6)],
            blocks: [
                TemplateBlock(
                    steps: [TemplateStep(kind: .work, goal: .distance(.fixed(400)))],
                    repetitions: .parameter("reps")
                ),
            ]
        )

        let workout = try template.instantiate(values: ["reps": 7.9])

        #expect(workout.blocks.map(\.repetitions) == [8])
    }

    @Test("instantiate carries an open goal through unchanged")
    func carriesOpenGoal() throws {
        let template = WorkoutTemplate(
            name: "Cooldown",
            sport: .running,
            parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .cooldown, goal: .open)])]
        )

        let workout = try template.instantiate()

        #expect(workout.blocks == [WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .open)])])
    }

    @Test("instantiate throws undeclaredParameter for a .parameter key with no matching WorkoutTemplateParameter")
    func throwsForUndeclaredParameter() {
        let template = WorkoutTemplate(
            name: "Recovery run",
            sport: .running,
            parameters: [],
            blocks: [
                TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("duration")))]),
            ]
        )

        #expect(throws: WorkoutTemplateError.undeclaredParameter("duration")) {
            try template.instantiate()
        }
    }

    @Test("expectedLoad matches estimating the instantiated workout directly")
    func expectedLoadMatchesInstantiatedWorkout() throws {
        let template = WorkoutTemplate(
            name: "Recovery run",
            sport: .running,
            parameters: [WorkoutTemplateParameter(key: "duration", name: "Duration", unit: .minutes, defaultValue: 20 * 60)],
            blocks: [
                TemplateBlock(steps: [
                    TemplateStep(kind: .work, goal: .time(.parameter("duration")), target: .heartRateZone(1)),
                ]),
            ]
        )
        let athlete = AthleteProfile.fixture()
        let estimator = TRIMPPlanEstimator()

        let expected = estimator.estimatedLoad(for: try template.instantiate(values: ["duration": 30 * 60.0]), athlete: athlete)
        let actual = try template.expectedLoad(values: ["duration": 30 * 60.0], estimator: estimator, athlete: athlete)

        #expect(actual.value == expected.value)
        #expect(actual.confidence == expected.confidence)
    }

    @Test("WorkoutTemplate round-trips through JSON encoding")
    func codableRoundTrip() throws {
        let template = WorkoutTemplate(
            name: "Intervals",
            sport: .running,
            parameters: [
                WorkoutTemplateParameter(key: "reps", name: "Repetitions", unit: .count, defaultValue: 6, range: 4...10),
            ],
            blocks: [
                TemplateBlock(
                    steps: [TemplateStep(kind: .work, goal: .distance(.fixed(400)), target: .heartRateZone(4))],
                    repetitions: .parameter("reps")
                ),
            ]
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: data)

        #expect(decoded == template)
    }
}

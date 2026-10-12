import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutPurpose")
struct WorkoutPurposeTests {
    private func duration(_ template: WorkoutTemplate) throws -> TimeInterval {
        try WorkoutDurationEstimator().duration(for: template.instantiate(), athlete: .fixture())
    }

    @Test("a template's purpose is carried to the workout it instantiates, and defaults to general")
    func carriedToWorkout() throws {
        let test = WorkoutTemplate(
            name: "Test", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .open)])], purpose: .maxHRTest
        )
        #expect(try test.instantiate().purpose == .maxHRTest)
        #expect(try BuiltInWorkoutTemplates.easyRun.instantiate().purpose == .general)
    }

    @Test("a workout or template saved before purposes existed decodes as general")
    func legacyDecodesAsGeneral() throws {
        let workout = StructuredWorkout(name: "Old", sport: .running, blocks: [], purpose: .lthrTest)
        let template = try BuiltInWorkoutTemplates.lthrTest

        func withoutPurpose<T: Codable>(_ value: T) throws -> Data {
            var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            #expect(json.removeValue(forKey: "purpose") != nil)
            return try JSONSerialization.data(withJSONObject: json)
        }

        #expect(try JSONDecoder().decode(StructuredWorkout.self, from: withoutPurpose(workout)).purpose == .general)
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: withoutPurpose(template)).purpose == .general)
    }

    @Test("purpose survives an encode and decode")
    func roundTrips() throws {
        for purpose in WorkoutPurpose.allCases {
            let workout = StructuredWorkout(name: "W", sport: .running, blocks: [], purpose: purpose)
            #expect(try JSONDecoder().decode(StructuredWorkout.self, from: JSONEncoder().encode(workout)) == workout)
        }
    }

    @Test("only the two field tests have a purpose among the built-ins")
    func builtInPurposes() {
        let tests = BuiltInWorkoutTemplates.all.filter { $0.purpose != .general }
        #expect(tests.map(\.id) == [BuiltInWorkoutTemplates.maxHRTest.id, BuiltInWorkoutTemplates.lthrTest.id])
        #expect(BuiltInWorkoutTemplates.maxHRTest.purpose == .maxHRTest)
        #expect(BuiltInWorkoutTemplates.lthrTest.purpose == .lthrTest)
    }

    @Test("the max HR test is a warmup, three 3-minute hard efforts with 1-minute recoveries, then a 3-minute all-out effort")
    func maxHRTestProtocol() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(300), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(180), target: .rpe(9)),
                    WorkoutStep(kind: .recovery, goal: .time(60), target: .heartRateZone(1)),
                ],
                repetitions: 3
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(180), target: .rpe(10))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300), target: .heartRateZone(1))]),
        ])
        #expect(workout.purpose == .maxHRTest)
        #expect(try duration(BuiltInWorkoutTemplates.maxHRTest) == 600 + 300 + 3 * 240 + 180 + 300)
    }

    @Test("the LTHR test is a warmup, one 30-minute effort, and a cooldown")
    func lthrTestProtocol() throws {
        let workout = try BuiltInWorkoutTemplates.lthrTest.instantiate()

        #expect(workout.blocks == [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(300), target: .heartRateZone(2))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(30 * 60), target: .rpe(9))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300), target: .heartRateZone(1))]),
        ])
        #expect(workout.purpose == .lthrTest)
        #expect(try duration(BuiltInWorkoutTemplates.lthrTest) == 600 + 300 + 30 * 60 + 300)
    }

    @Test("a calendar file keeps a template's purpose, and reads an unknown one as general")
    func calendarFileKeepsPurpose() throws {
        let file = CalendarExport.Template(BuiltInWorkoutTemplates.lthrTest)
        #expect(file.workoutTemplate()?.purpose == .lthrTest)

        let ordinary = CalendarExport.Template(BuiltInWorkoutTemplates.easyRun)
        #expect(ordinary.purpose == nil)
        #expect(ordinary.workoutTemplate()?.purpose == .general)

        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
        json["purpose"] = "vo2maxTest"
        let future = try JSONDecoder().decode(CalendarExport.Template.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(future.workoutTemplate()?.purpose == .general)
    }
}

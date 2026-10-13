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
        let template = BuiltInWorkoutTemplates.lthrTest

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

    private func step(_ kind: StepKind, _ seconds: TimeInterval, _ target: IntensityTarget) -> WorkoutStep {
        WorkoutStep(kind: kind, goal: .time(seconds), target: target)
    }

    @Test("the max HR test is a warmup, three 3-minute hard efforts with 1-minute recoveries, then a 3-minute all-out effort")
    func maxHRTestProtocol() throws {
        let workout = try BuiltInWorkoutTemplates.maxHRTest.instantiate()

        let warmup = WorkoutBlock(steps: [step(.warmup, 600, .heartRateZone(1))])
        let rampIn = WorkoutBlock(steps: [step(.work, 300, .heartRateZone(2))])
        let efforts = WorkoutBlock(
            steps: [step(.work, 180, .rpe(9)), step(.recovery, 60, .heartRateZone(1))], repetitions: 3
        )
        let allOut = WorkoutBlock(steps: [step(.work, 180, .rpe(10))])
        let cooldown = WorkoutBlock(steps: [step(.cooldown, 300, .heartRateZone(1))])
        let expected: [WorkoutBlock] = [warmup, rampIn, efforts, allOut, cooldown]

        #expect(workout.blocks == expected)
        #expect(workout.purpose == .maxHRTest)
        #expect(try duration(BuiltInWorkoutTemplates.maxHRTest) == 600 + 300 + 3 * 240 + 180 + 300)
    }

    @Test("the LTHR test is a warmup, one 30-minute effort, and a cooldown")
    func lthrTestProtocol() throws {
        let workout = try BuiltInWorkoutTemplates.lthrTest.instantiate()

        let warmup = WorkoutBlock(steps: [step(.warmup, 600, .heartRateZone(1))])
        let rampIn = WorkoutBlock(steps: [step(.work, 300, .heartRateZone(2))])
        let effort = WorkoutBlock(steps: [step(.work, 30 * 60, .rpe(9))])
        let cooldown = WorkoutBlock(steps: [step(.cooldown, 300, .heartRateZone(1))])
        let expected: [WorkoutBlock] = [warmup, rampIn, effort, cooldown]

        #expect(workout.blocks == expected)
        #expect(workout.purpose == .lthrTest)
        #expect(try duration(BuiltInWorkoutTemplates.lthrTest) == 600 + 300 + 30 * 60 + 300)
    }

    @Test("editing a workout's blocks, or its template's purpose later, leaves the instantiated purpose alone")
    func purposeIsFixedAtInstantiation() throws {
        var template = BuiltInWorkoutTemplates.maxHRTest
        var workout = try template.instantiate()

        workout.blocks = []
        template.purpose = .general

        #expect(workout.purpose == .maxHRTest)
        #expect(try template.instantiate().purpose == .general)
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

import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutTemplate default title")
struct WorkoutTemplateDefaultTitleTests {
    @Test("a duration template is the main duration and the capitalized name")
    func durationTemplates() {
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle(values: ["duration": 50 * 60]) == "50min Easy Run")
        #expect(BuiltInWorkoutTemplates.recoveryRun.defaultTitle() == "20min Recovery Run")
        // The 5-minute `.work` ramp-in doesn't win over the main effort.
        #expect(BuiltInWorkoutTemplates.tempoRun.defaultTitle(values: ["duration": 30 * 60]) == "30min Tempo Run")
    }

    @Test("a distance template is the main distance")
    func distanceTemplate() {
        #expect(BuiltInWorkoutTemplates.longRun.defaultTitle(values: ["distance": 23_000]) == "23 km Long Run")
        #expect(BuiltInWorkoutTemplates.longRun.defaultTitle(values: ["distance": 21_500]) == "21.5 km Long Run")
    }

    @Test("distances can be written in miles")
    func miles() {
        let title = BuiltInWorkoutTemplates.longRun.defaultTitle(values: ["distance": 21_097], distanceSystem: .imperial)
        #expect(title == "13.1 mi Long Run")
    }

    @Test("an interval template is reps x effort, using the short title name")
    func intervals() {
        #expect(BuiltInWorkoutTemplates.baseHillSprints.defaultTitle(values: ["reps": 10]) == "10x8sec Hill Sprints")
        #expect(BuiltInWorkoutTemplates.shortIntervalRun.defaultTitle(values: ["reps": 8, "work": 90]) == "8x90sec Short Interval Run")
        #expect(BuiltInWorkoutTemplates.shortIntervalRun.defaultTitle(values: ["reps": 8, "work": 120]) == "8x2min Short Interval Run")
        #expect(BuiltInWorkoutTemplates.shortIntervalRunTrack.defaultTitle(values: ["reps": 6, "distance": 400])
                == "6x400 m Short Interval Run (Track)")
        #expect(BuiltInWorkoutTemplates.shortIntervalRunTrack.defaultTitle(values: ["distance": 1200]).contains("1.2 km"))
    }

    @Test("the title follows the defaults when no values are given")
    func defaults() {
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle() == "30min Easy Run")
        #expect(BuiltInWorkoutTemplates.baseHillSprints.defaultTitle() == "6x8sec Hill Sprints")
    }

    @Test("long durations use hours")
    func hours() {
        let template = WorkoutTemplate(
            name: "steady", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "d", name: "D", unit: .minutes, defaultValue: 0)],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("d")), target: .heartRateZone(2))])]
        )
        #expect(template.defaultTitle(values: ["d": 5400]) == "1h30min Steady")
        #expect(template.defaultTitle(values: ["d": 7200]) == "2h Steady")
    }

    @Test("a workout with only open steps, or a bad reference, is just the name")
    func fallbacks() {
        let open = WorkoutTemplate(
            name: "free run", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .open, target: .heartRateZone(2))])]
        )
        #expect(open.defaultTitle() == "Free Run")

        let broken = WorkoutTemplate(
            name: "broken", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("missing")), target: .heartRateZone(2))])]
        )
        #expect(broken.defaultTitle() == "Broken")
    }

    @Test("titleName survives encoding, and a template encoded without it still decodes")
    func codable() throws {
        let template = BuiltInWorkoutTemplates.baseHillSprints
        let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: JSONEncoder().encode(template))
        #expect(decoded.titleName == "Hill Sprints")

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
        object["titleName"] = nil
        let legacy = try JSONDecoder().decode(WorkoutTemplate.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.titleName == nil)
    }
}

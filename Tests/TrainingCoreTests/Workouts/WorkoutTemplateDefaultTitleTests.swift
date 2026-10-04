import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutTemplate default title")
struct WorkoutTemplateDefaultTitleTests {
    @Test("a duration template is its total time, warmup and cooldown included")
    func durationTemplates() {
        // 5 min warmup + 30 min + 5 min cooldown.
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle() == "40min Easy Run")
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle(values: ["duration": 45 * 60]) == "55min Easy Run")
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle(values: ["duration": 50 * 60]) == "1h Easy Run")
        #expect(BuiltInWorkoutTemplates.recoveryRun.defaultTitle() == "20min Recovery Run")
        // 5 + 5 ramp-in + 30 + 5 recovery + 5.
        #expect(BuiltInWorkoutTemplates.tempoRun.defaultTitle(values: ["duration": 30 * 60]) == "50min Tempo Run")
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
        #expect(BuiltInWorkoutTemplates.shortIntervalRunTrack.defaultTitle(values: ["distance": 1200]) == "8x1.2 km Short Interval Run (Track)")
    }

    @Test("short imperial efforts are in yards, never 0 mi")
    func imperialYards() {
        let track = BuiltInWorkoutTemplates.shortIntervalRunTrack
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 400], distanceSystem: .imperial) == "8x440 yd Short Interval Run (Track)")
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 50], distanceSystem: .imperial) == "8x50 yd Short Interval Run (Track)")
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 800], distanceSystem: .imperial) == "8x870 yd Short Interval Run (Track)")
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 1609.344], distanceSystem: .imperial) == "8x1 mi Short Interval Run (Track)")
    }

    @Test("the metric unit is chosen after rounding")
    func metricBoundary() {
        let track = BuiltInWorkoutTemplates.shortIntervalRunTrack
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 999.6]) == "8x1 km Short Interval Run (Track)")
        #expect(track.defaultTitle(values: ["reps": 8, "distance": 999.4]) == "8x999 m Short Interval Run (Track)")
    }

    @Test("non-finite and negative goals fall back to the name instead of trapping")
    func unusableValues() {
        let easy = BuiltInWorkoutTemplates.easyRun
        for bad in [Double.nan, .infinity, -.infinity, -300] {
            #expect(easy.defaultTitle(values: ["duration": bad]) == "Easy Run")
        }
        let hills = BuiltInWorkoutTemplates.shortIntervalRun
        #expect(hills.defaultTitle(values: ["work": .nan]) == "Short Interval Run")
    }

    @Test("open-ended steps add nothing to a steady workout's total")
    func openStepsAreIgnored() {
        let template = WorkoutTemplate(
            name: "run to the hill", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [
                TemplateStep(kind: .warmup, goal: .time(.fixed(300)), target: .heartRateZone(1)),
                TemplateStep(kind: .work, goal: .open, target: .heartRateZone(2)),
                TemplateStep(kind: .cooldown, goal: .time(.fixed(300)), target: .heartRateZone(1)),
            ])]
        )
        #expect(template.defaultTitle() == "10min Run To The Hill")
    }

    @Test("a zero main step adds nothing, but a zero interval effort is just the name")
    func zeroGoals() {
        #expect(BuiltInWorkoutTemplates.easyRun.defaultTitle(values: ["duration": 0]) == "10min Easy Run")
        #expect(BuiltInWorkoutTemplates.shortIntervalRun.defaultTitle(values: ["work": 0]) == "Short Interval Run")
    }

    @Test("a fractional repetition count rounds the way instantiate does")
    func fractionalReps() {
        #expect(BuiltInWorkoutTemplates.baseHillSprints.defaultTitle(values: ["reps": 7.9]) == "8x8sec Hill Sprints")
    }

    @Test("the title follows the defaults when no values are given")
    func defaults() {
        #expect(BuiltInWorkoutTemplates.longRun.defaultTitle() == "20 km Long Run")
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

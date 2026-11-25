import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutTemplate watch screen set (WATCH-133)")
struct WorkoutTemplateWatchScreenSetTests {
    private func template(setID: String? = nil) -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Sprints", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .open, target: .none)])],
            watchScreenSetID: setID)
    }

    @Test("the screen set id round-trips, and is left out of the stored form when there is none")
    func coding() throws {
        let linked = template(setID: "sprint")
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: JSONEncoder().encode(linked)).watchScreenSetID == "sprint")

        let data = try JSONEncoder().encode(template())
        #expect(!String(decoding: data, as: UTF8.self).contains("watchScreenSetID"))
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: data).watchScreenSetID == nil)
    }

    @Test("two templates that differ only in the screen set are not equal")
    func equality() {
        var a = template(setID: "a")
        var b = a
        #expect(a == b)
        b.watchScreenSetID = nil
        #expect(a != b)
        a.watchScreenSetID = nil
        #expect(a == b)
    }

    @Test("the built-in templates have no screen set")
    func builtIns() {
        #expect(BuiltInWorkoutTemplates.all.allSatisfy { $0.watchScreenSetID == nil })
    }
}

import Foundation
import Testing
@testable import TrainingPersistence
import TrainingCore

/// A workout and a template with zone positions (MVP5-148) survive the stores, in memory and in SwiftData.
@Suite("Zone positions in the stores")
struct SwiftDataZonePositionTests {
    private let workout = StructuredWorkout(
        name: "Z3.0-3.4", sport: .running,
        blocks: [WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZoneRange(3.0...3.4), companionTarget: .pace(262...270)),
            WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(1)),
        ], repetitions: 4)]
    )

    @Test("the target and a workout with it round trip through JSON")
    func coding() throws {
        let target = IntensityTarget.heartRateZoneRange(3.0...3.4)
        #expect(try JSONDecoder().decode(IntensityTarget.self, from: JSONEncoder().encode(target)) == target)
        #expect(try JSONDecoder().decode(StructuredWorkout.self, from: JSONEncoder().encode(workout)) == workout)
    }

    @Test("the library of both stores returns the workout with its positions")
    func libraryRoundTrip() async throws {
        let memory = InMemoryStore()
        try await memory.upsert([workout])
        #expect(try await memory.workouts().first { $0.id == workout.id } == workout)

        let container = try TestContainers.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let swiftData = SwiftDataStore(modelContainer: container)
        try await swiftData.upsert([workout])
        #expect(try await swiftData.workouts().first { $0.id == workout.id } == workout)
    }

    @Test("a template with positions round trips through JSON and instantiates with them")
    func templateRoundTrip() throws {
        let template = WorkoutTemplate(
            name: "Z3 start", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(600)), target: .heartRateZoneRange(3.0...3.4))])],
            sessionType: .tempo
        )
        let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: JSONEncoder().encode(template))
        #expect(decoded == template)
        #expect(try decoded.instantiate().blocks[0].steps[0].target == IntensityTarget.heartRateZoneRange(3.0...3.4))
    }
}

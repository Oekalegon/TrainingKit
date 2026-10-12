import Foundation
import Testing
import TrainingCore
@testable import TrainingPersistence

@Suite("WorkoutPurpose + SwiftData")
struct SwiftDataWorkoutPurposeTests {
    @Test("a workout and a template keep their purpose through the records (MVP2-153)")
    func purposeSurvivesRecords() async throws {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        let store = SwiftDataStore(modelContainer: container)
        let template = BuiltInWorkoutTemplates.maxHRTest
        let workout = try template.instantiate()

        try await store.upsert([template])
        try await store.upsert([workout])

        #expect(try await store.template(id: template.id)?.purpose == .maxHRTest)
        #expect(try await store.workout(id: workout.id)?.purpose == .maxHRTest)
    }
}

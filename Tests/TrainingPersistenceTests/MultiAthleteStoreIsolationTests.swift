import Foundation
import Testing
@testable import TrainingPersistence
import TrainingCore

/// Proves container-per-athlete isolation holds at the SwiftData layer, not just `InMemoryStore`:
/// two independently constructed `SwiftDataStore`s, each backed by its own `ModelContainer`, never
/// see each other's `AthleteProfile` — the pattern the design doc's "Multiple athletes" section
/// describes a host coaching app would rely on.
@Suite("Multi-athlete SwiftDataStore isolation")
struct MultiAthleteStoreIsolationTests {
    private func makeStore() throws -> SwiftDataStore {
        let container = try TrainingPersistenceContainer.make(cloudKitDatabase: .none, isStoredInMemoryOnly: true)
        return SwiftDataStore(modelContainer: container)
    }

    @Test("two SwiftDataStores, each its own container, hold distinct athlete profiles with no cross-contamination")
    func separateContainersIsolateProfiles() async throws {
        let storeA = try makeStore()
        let storeB = try makeStore()

        let athleteA = AthleteProfile.fixture(name: "Athlete A")
        let athleteB = AthleteProfile.fixture(name: "Athlete B")
        #expect(athleteA.id != athleteB.id)

        try await storeA.save(athleteA)
        try await storeB.save(athleteB)

        let fetchedA = try await storeA.athleteProfile()
        let fetchedB = try await storeB.athleteProfile()

        #expect(fetchedA?.id == athleteA.id)
        #expect(fetchedA?.name == "Athlete A")
        #expect(fetchedB?.id == athleteB.id)
        #expect(fetchedB?.name == "Athlete B")
    }
}

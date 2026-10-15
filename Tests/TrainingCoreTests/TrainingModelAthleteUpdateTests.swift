import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel.updateAthlete", .serialized)
struct TrainingModelAthleteUpdateTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel(athleteStore: any AthleteStore) -> TrainingModel {
        let base = InMemoryStore()
        let stores = StoreSet(
            activityStore: base, planStore: base, workoutStore: base,
            cycleStore: base, raceStore: base, athleteStore: athleteStore
        )
        return TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178))
    }

    /// A resting-HR change effective `date`, as a HealthKit refresh would append.
    private func appendingResting(_ bpm: Double, on date: Date) -> @Sendable (AthleteProfile) -> AthleteProfile {
        { athlete in
            var updated = athlete
            var entry = athlete.currentHeartRateZoneSettings!
            entry.effectiveDate = date
            entry.restingHeartRateBPM = bpm
            updated.heartRateZoneHistory.append(entry)
            return updated
        }
    }

    @Test("an update is saved, assigned and reported as a change")
    func updateSavesAndAssigns() async throws {
        let store = RecordingAthleteStore()
        let model = makeModel(athleteStore: store)

        let changed = try await model.updateAthlete(asOf: day(10), appendingResting(45, on: day(5)))

        #expect(changed)
        #expect(model.athlete.currentHeartRateZoneSettings?.restingHeartRateBPM == 45)
        #expect(await store.saved.last == model.athlete)
    }

    @Test("a transform that changes nothing doesn't save")
    func noChangeNoSave() async throws {
        let store = RecordingAthleteStore()
        let model = makeModel(athleteStore: store)

        let changed = try await model.updateAthlete(asOf: day(10)) { $0 }

        #expect(!changed)
        #expect(await store.saved.isEmpty)
    }

    @Test("a failed save leaves the athlete unchanged")
    func failedSaveChangesNothing() async throws {
        let store = RecordingAthleteStore(failSaves: true)
        let model = makeModel(athleteStore: store)
        let before = model.athlete

        await #expect(throws: RecordingAthleteStore.SaveError.self) {
            try await model.updateAthlete(asOf: day(10), appendingResting(45, on: day(5)))
        }
        #expect(model.athlete == before)
    }

    @Test("a max HR update and a HealthKit refresh started together both survive, in the model and the store")
    func concurrentUpdatesBothSurvive() async throws {
        let store = RecordingAthleteStore(saveDelay: .milliseconds(20))
        let model = makeModel(athleteStore: store)
        let suggestion = MaxHeartRateSuggestion(
            activityID: UUID(), sport: .running, activityStart: day(2), peakBPM: 189, currentMaxBPM: 178
        )

        async let raise: Void = model.applyMaxHeartRate(suggestion, asOf: day(10))
        async let refresh = model.updateAthlete(asOf: day(10), appendingResting(45, on: day(5)))
        _ = try await (raise, refresh)

        let current = try #require(model.athlete.currentHeartRateZoneSettings)
        #expect(current.restingHeartRateBPM == 45)
        #expect(current.maxHeartRateBPM == 189)
        #expect(model.athlete.heartRateZoneSettings(asOf: day(2))?.maxHeartRateBPM == 189)
        #expect(await store.saved.last == model.athlete)
    }
}

/// An ``AthleteStore`` that records every saved profile, optionally slowly or failing.
private actor RecordingAthleteStore: AthleteStore {
    struct SaveError: Error {}
    private(set) var saved: [AthleteProfile] = []
    private var anchor: ImportAnchor?
    private let saveDelay: Duration?
    private let failSaves: Bool

    init(saveDelay: Duration? = nil, failSaves: Bool = false) {
        self.saveDelay = saveDelay
        self.failSaves = failSaves
    }

    func athleteProfile() async throws -> AthleteProfile? { saved.last }

    func save(_ profile: AthleteProfile) async throws {
        if let saveDelay { try await Task.sleep(for: saveDelay) }
        if failSaves { throw SaveError() }
        saved.append(profile)
    }

    func importAnchor() async throws -> ImportAnchor? { anchor }
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws { self.anchor = anchor }
}

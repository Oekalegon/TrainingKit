import Foundation
import Testing
@testable import TrainingCore

@MainActor
@Suite("TrainingModel max heart rate", .serialized)
struct TrainingModelMaxHeartRateTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// The fixture athlete's calendar (UTC), so day matching doesn't depend on the test machine's
    /// time zone.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeModel(maxHeartRateBPM: Double = 178) -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture(maxHeartRateBPM: maxHeartRateBPM)))
    }

    /// A run at 150 bpm that ramps up 10 bpm per 5 s sample (a real heart's pace, below the
    /// detector's cadence-lock threshold) to hold `peak` for two minutes, then ramps back down.
    private func run(on start: Date, peak: Double) -> Activity {
        let ramp = stride(from: 150.0, to: peak, by: 10).dropFirst().map { $0 }
        let bpms = Array(repeating: 150.0, count: 48) + ramp + Array(repeating: peak, count: 24)
            + ramp.reversed() + Array(repeating: 150.0, count: 48)
        let samples = bpms.enumerated().map { index, bpm in
            HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm)
        }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 600, heartRate: samples)
    }

    @Test("no suggestion when no activity beats the current max")
    func noSuggestionBelowMax() {
        let (_, model) = makeModel()

        #expect(model.maxHeartRateSuggestion(among: [run(on: day(1), peak: 176), run(on: day(2), peak: 178)]) == nil)
    }

    @Test("the activity with the highest held peak above the max is suggested")
    func highestPeakSuggested() {
        let (_, model) = makeModel()
        let lower = run(on: day(1), peak: 183)
        let higher = run(on: day(2), peak: 189)

        let suggestion = model.maxHeartRateSuggestion(among: [lower, higher])

        #expect(suggestion?.activityID == higher.id)
        #expect(suggestion?.peakBPM == 189)
        #expect(suggestion?.currentMaxBPM == 178)
        #expect(suggestion?.sport == .running)
        #expect(suggestion?.activityStart == day(2))
    }

    @Test("a peak must be at least 1 bpm above an unrounded current max")
    func roundingNeedsWholeBeatAboveMax() {
        let (_, model) = makeModel(maxHeartRateBPM: 178.4)

        #expect(model.maxHeartRateSuggestion(among: [run(on: day(1), peak: 179)]) == nil)
        #expect(model.maxHeartRateSuggestion(among: [run(on: day(1), peak: 180)])?.peakBPM == 180)
    }

    @Test("a single high sample doesn't produce a suggestion")
    func spikeDoesNotSuggest() {
        let (_, model) = makeModel()
        var activity = run(on: day(1), peak: 170)
        activity.heartRate[60] = HeartRateSample(time: activity.heartRate[60].time, bpm: 205)

        #expect(model.maxHeartRateSuggestion(among: [activity]) == nil)
    }

    @Test("the history scan reads the store, not just the loaded activities")
    func scanReadsStore() async throws {
        let (store, model) = makeModel()
        let old = run(on: day(-200), peak: 187)
        try await store.upsert([old])

        let suggestion = try await model.scanForMaxHeartRateSuggestion(in: day(-365)...day(0))

        #expect(model.activities.isEmpty)
        #expect(suggestion?.activityID == old.id)
    }

    @Test("the history scan skips excluded activities and suggests the next best")
    func scanSkipsExcluded() async throws {
        let (store, model) = makeModel()
        let declined = run(on: day(-100), peak: 191)
        let next = run(on: day(-50), peak: 185)
        try await store.upsert([declined, next])

        let suggestion = try await model.scanForMaxHeartRateSuggestion(in: day(-365)...day(0), excluding: [declined.id])

        #expect(suggestion?.activityID == next.id)
    }

    @Test("applying raises max from the activity's date, saves the profile, and lowers that activity's inflated load")
    func applyRaisesSavesAndRecomputes() async throws {
        let (store, model) = makeModel()
        let activity = run(on: day(5), peak: 189)
        try await store.upsert([activity])
        try await model.load(in: day(0)...day(10), asOf: day(10))
        let loadBefore = try #require(model.metrics.first { utc.isDate($0.day, inSameDayAs: day(5)) }?.load)
        let suggestion = try #require(model.maxHeartRateSuggestion(among: model.activities))

        try await model.applyMaxHeartRate(suggestion, asOf: day(10))

        #expect(model.athlete.heartRateZoneSettings(asOf: day(4))?.maxHeartRateBPM == 178)
        let raised = model.athlete.heartRateZoneSettings(asOf: day(5))
        #expect(raised?.maxHeartRateBPM == 189)
        #expect(raised?.maxHeartRateSource == .workout(activityID: activity.id))
        #expect(try await store.athleteProfile() == model.athlete)
        let loadAfter = try #require(model.metrics.first { utc.isDate($0.day, inSameDayAs: day(5)) }?.load)
        #expect(loadAfter < loadBefore)
        #expect(model.maxHeartRateSuggestion(among: model.activities) == nil)
    }

    @Test("a failed save leaves the athlete unchanged")
    func failedSaveChangesNothing() async throws {
        let store = FailingAthleteSaveStore()
        let stores = StoreSet(
            activityStore: store.base, planStore: store.base, workoutStore: store.base,
            cycleStore: store.base, raceStore: store.base, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(maxHeartRateBPM: 178))
        let suggestion = MaxHeartRateSuggestion(
            activityID: UUID(), sport: .running, activityStart: day(5), peakBPM: 189, currentMaxBPM: 178
        )

        await #expect(throws: FailingAthleteSaveStore.SaveError.self) {
            try await model.applyMaxHeartRate(suggestion, asOf: day(10))
        }
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 178)
    }
}

/// An ``AthleteStore`` whose `save` always fails, for the failure path.
private final class FailingAthleteSaveStore: AthleteStore, @unchecked Sendable {
    struct SaveError: Error {}
    let base = InMemoryStore()

    func athleteProfile() async throws -> AthleteProfile? { try await base.athleteProfile() }
    func save(_ profile: AthleteProfile) async throws { throw SaveError() }
    func importAnchor() async throws -> ImportAnchor? { try await base.importAnchor() }
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws { try await base.saveImportAnchor(anchor) }
}

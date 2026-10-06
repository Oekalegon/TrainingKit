import Foundation
import Testing
@testable import TrainingCore

@Suite("AthleteProfile editing (MVP2-132)")
struct AthleteProfileEditingTests {
    private func date(_ month: Int, _ day: Int, hour: Int = 12, in identifier: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func settings(on day: Date, resting: Double = 50, max: Double = 190, method: HeartRateZoneMethod = .karvonen) -> HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: day, restingHeartRateBPM: resting, maxHeartRateBPM: max,
            maxHeartRateSource: .manual, zoneMethod: method
        )
    }

    // MARK: Heart-rate settings

    @Test("recording on a new day adds an entry from the start of that day")
    func recordingAddsAnEntryFromTheStartOfTheDay() {
        let athlete = AthleteProfile.fixture()

        let updated = athlete.recordingHeartRateSettings(settings(on: date(6, 10, hour: 15), resting: 48, max: 186))

        #expect(updated.heartRateZoneHistory.count == 2)
        let entry = updated.heartRateZoneSettings(asOf: date(6, 10, hour: 0))
        #expect(entry?.maxHeartRateBPM == 186)
        #expect(entry?.maxHeartRateSource == .manual)
        // The morning of that day already uses it; the evening before doesn't.
        #expect(updated.heartRateZoneSettings(asOf: date(6, 9, hour: 23))?.maxHeartRateBPM == 190)
    }

    @Test("recording on a day that already has an entry replaces it, however its time of day differs")
    func recordingReplacesTheSameDay() {
        let athlete = AthleteProfile.fixture().recordingHeartRateSettings(settings(on: date(6, 10, hour: 9), max: 186))

        let updated = athlete.recordingHeartRateSettings(settings(on: date(6, 10, hour: 18), max: 188))

        #expect(updated.heartRateZoneHistory.count == 2)
        #expect(updated.currentHeartRateZoneSettings?.maxHeartRateBPM == 188)
    }

    @Test("the day is the athlete's, not UTC's")
    func recordingUsesTheAthletesTimeZone() {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Pacific/Auckland")
        // 2026-06-10 08:00 Auckland is 2026-06-09 20:00 UTC: still the 10th for the athlete.
        let updated = athlete.recordingHeartRateSettings(settings(on: date(6, 10, hour: 8, in: "Pacific/Auckland")))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        #expect(updated.currentHeartRateZoneSettings?.effectiveDate == calendar.startOfDay(for: date(6, 10, hour: 8, in: "Pacific/Auckland")))
    }

    @Test("removing an entry drops its day, but the last entry stays")
    func removingKeepsTheLastEntry() {
        let athlete = AthleteProfile.fixture().recordingHeartRateSettings(settings(on: date(6, 10)))

        let removed = athlete.removingHeartRateSettings(on: date(6, 10, hour: 3))
        #expect(removed.heartRateZoneHistory.count == 1)

        let onlyOne = removed.removingHeartRateSettings(on: .distantPast)
        #expect(onlyOne == removed)
        // No entry that day: nothing to remove.
        #expect(athlete.removingHeartRateSettings(on: date(7, 1)) == athlete)
    }

    // MARK: Pace history

    @Test("a profile built with one pace model has it as its only entry, since the beginning of time")
    func initialPaceHistory() {
        let athlete = AthleteProfile.fixture(thresholdPaceSecondsPerKilometer: 300)

        #expect(athlete.paceHistory.count == 1)
        #expect(athlete.paceHistory[0].effectiveDate == .distantPast)
        #expect(athlete.paceModel.thresholdPaceSecondsPerKilometer == 300)
    }

    @Test("an empty pace history given to the initializer counts as none: the pace model becomes the one entry")
    func emptyPaceHistoryFallsBack() {
        let athlete = AthleteProfile(
            sex: .male, paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 255),
            timeZone: TimeZone(identifier: "UTC")!, heartRateZoneHistory: [], paceHistory: []
        )

        #expect(athlete.paceHistory.count == 1)
        #expect(athlete.paceModel.thresholdPaceSecondsPerKilometer == 255)
    }

    @Test("a recorded pace is dated; paceModel is the latest, paceModel(asOf:) the one in effect then")
    func recordedPaceIsDated() {
        let athlete = AthleteProfile.fixture(thresholdPaceSecondsPerKilometer: 300)
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 280), from: date(6, 10))

        #expect(athlete.paceModel.thresholdPaceSecondsPerKilometer == 280)
        #expect(athlete.paceModel(asOf: date(6, 9)).thresholdPaceSecondsPerKilometer == 300)
        #expect(athlete.paceModel(asOf: date(6, 10, hour: 1)).thresholdPaceSecondsPerKilometer == 280)
        #expect(athlete.paceModel(asOf: .distantPast).thresholdPaceSecondsPerKilometer == 300)
    }

    @Test("recording a pace on a day with an entry replaces it; removing keeps the last entry")
    func paceReplaceAndRemove() {
        let athlete = AthleteProfile.fixture()
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 280), from: date(6, 10, hour: 8))
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 270), from: date(6, 10, hour: 20))

        #expect(athlete.paceHistory.count == 2)
        #expect(athlete.paceModel.thresholdPaceSecondsPerKilometer == 270)

        let removed = athlete.removingPaceSettings(on: date(6, 10))
        #expect(removed.paceHistory.count == 1)
        #expect(removed.removingPaceSettings(on: .distantPast) == removed)
    }

    @Test("assigning paceModel replaces the latest entry's model")
    func paceModelSetter() {
        var athlete = AthleteProfile.fixture()
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 280), from: date(6, 10))

        athlete.paceModel = PaceModel(thresholdPaceSecondsPerKilometer: 400)

        #expect(athlete.paceHistory.count == 2)
        #expect(athlete.paceModel.thresholdPaceSecondsPerKilometer == 400)
        #expect(athlete.paceModel(asOf: date(6, 9)).thresholdPaceSecondsPerKilometer == 240)
    }

    // MARK: Coding

    @Test("a profile stored before the pace history and the HealthKit switch existed decodes both")
    func decodesLegacyPayload() throws {
        let original = AthleteProfile.fixture(thresholdPaceSecondsPerKilometer: 310)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "paceHistory")
        object.removeValue(forKey: "usesHealthKitRestingHeartRate")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: legacy)

        #expect(decoded.paceHistory.count == 1)
        #expect(decoded.paceHistory[0].effectiveDate == .distantPast)
        #expect(decoded.paceModel.thresholdPaceSecondsPerKilometer == 310)
        #expect(decoded.usesHealthKitRestingHeartRate)
    }

    @Test("the history and the switch round-trip, and the current pace is also written under its old key")
    func roundTrips() throws {
        var original = AthleteProfile.fixture()
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 280), from: date(6, 10))
        original.usesHealthKitRestingHeartRate = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        #expect(decoded == original)
        #expect(!decoded.usesHealthKitRestingHeartRate)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let oldKey = try #require(object["paceModel"] as? [String: Any])
        #expect(oldKey["thresholdPaceSecondsPerKilometer"] as? Double == 280)
    }

    @Test("the avatar image round-trips, and a profile without one decodes with none")
    func avatarRoundTrips() throws {
        var original = AthleteProfile.fixture()
        #expect(original.avatarImageData == nil)
        original.avatarImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)
        #expect(decoded.avatarImageData == original.avatarImageData)
        #expect(decoded == original)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "avatarImageData")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(AthleteProfile.self, from: legacy).avatarImageData == nil)
    }

    @Test("a manually entered max heart rate source round-trips")
    func manualSourceRoundTrips() throws {
        let entry = settings(on: date(6, 10))

        let decoded = try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONEncoder().encode(entry))

        #expect(decoded.maxHeartRateSource == .manual)
    }
}

import Foundation
import Testing
@testable import TrainingCore

@Suite("AthleteProfile max heart rate")
struct AthleteProfileMaxHeartRateTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func settings(_ day: Date, max: Double, resting: Double = 50) -> HeartRateZoneSettings {
        HeartRateZoneSettings(effectiveDate: day, restingHeartRateBPM: resting, maxHeartRateBPM: max)
    }

    private func profile(_ history: [HeartRateZoneSettings]) -> AthleteProfile {
        var profile = AthleteProfile.fixture()
        profile.heartRateZoneHistory = history
        return profile
    }

    @Test("raising adds an entry from the given date and leaves earlier settings alone")
    func raisingAddsDatedEntry() {
        let activityID = UUID()
        let original = profile([settings(day(0), max: 178)])

        let raised = original.raisingMaxHeartRate(to: 189, from: day(10), source: .workout(activityID: activityID))

        #expect(raised.heartRateZoneSettings(asOf: day(5))?.maxHeartRateBPM == 178)
        let fromDate = raised.heartRateZoneSettings(asOf: day(10))
        #expect(fromDate?.maxHeartRateBPM == 189)
        #expect(fromDate?.maxHeartRateSource == .workout(activityID: activityID))
        #expect(fromDate?.restingHeartRateBPM == 50)
    }

    @Test("later lower entries are raised too, so a resting-HR update can't bring the old max back")
    func laterEntriesRaised() {
        let original = profile([settings(day(0), max: 178), settings(day(20), max: 178, resting: 48)])

        let raised = original.raisingMaxHeartRate(to: 189, from: day(10), source: .workout(activityID: UUID()))

        let later = raised.heartRateZoneSettings(asOf: day(25))
        #expect(later?.maxHeartRateBPM == 189)
        #expect(later?.restingHeartRateBPM == 48)
        #expect(raised.heartRateZoneHistory.count == 3)
    }

    @Test("raising never lowers: a peak at or below the max in effect changes nothing")
    func neverLowers() {
        let original = profile([settings(day(0), max: 190)])

        #expect(original.raisingMaxHeartRate(to: 185, from: day(10), source: .workout(activityID: UUID())) == original)
        #expect(original.raisingMaxHeartRate(to: 190, from: day(10), source: .workout(activityID: UUID())) == original)
    }

    @Test("an entry starting exactly at the date is raised in place rather than duplicated")
    func sameDateRaisedInPlace() {
        let original = profile([settings(day(0), max: 178), settings(day(10), max: 178, resting: 49)])

        let raised = original.raisingMaxHeartRate(to: 189, from: day(10), source: .workout(activityID: UUID()))

        #expect(raised.heartRateZoneHistory.count == 2)
        #expect(raised.heartRateZoneSettings(asOf: day(10))?.maxHeartRateBPM == 189)
        #expect(raised.heartRateZoneSettings(asOf: day(10))?.restingHeartRateBPM == 49)
    }

    @Test("a profile without heart-rate settings is returned unchanged")
    func noSettingsNoChange() {
        let original = profile([])

        #expect(original.raisingMaxHeartRate(to: 189, from: day(10), source: .formula) == original)
    }

    @Test("settings saved before maxHeartRateSource existed decode as formula-based")
    func legacyDecodesAsFormula() throws {
        let legacy = Data("""
            {"effectiveDate": 0, "restingHeartRateBPM": 50, "maxHeartRateBPM": 178, "zoneMethod": {"karvonen": {}}}
            """.utf8)

        let decoded = try JSONDecoder().decode(HeartRateZoneSettings.self, from: legacy)

        #expect(decoded.maxHeartRateSource == .formula)
        #expect(decoded.maxHeartRateBPM == 178)
    }

    @Test("a workout source round-trips through Codable")
    func workoutSourceRoundTrips() throws {
        let original = HeartRateZoneSettings(
            effectiveDate: day(3), restingHeartRateBPM: 50, maxHeartRateBPM: 189,
            maxHeartRateSource: .workout(activityID: UUID())
        )

        let decoded = try JSONDecoder().decode(HeartRateZoneSettings.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }
}

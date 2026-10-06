import Foundation
import Testing
@testable import TrainingCore

@Suite("AthleteProfile date of birth (MVP2-124)")
struct AthleteProfileDateOfBirthTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in identifier: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func profile(dateOfBirth: Date?, timeZone: String = "UTC") -> AthleteProfile {
        var profile = AthleteProfile.fixture(timeZoneIdentifier: timeZone)
        profile.dateOfBirth = dateOfBirth
        return profile
    }

    @Test("a profile without a date of birth has no age")
    func noDateOfBirthNoAge() {
        #expect(profile(dateOfBirth: nil).age(asOf: date(2026, 10, 6)) == nil)
    }

    @Test("age counts whole years and ticks over on the birthday itself")
    func ageTicksOverOnBirthday() {
        let athlete = profile(dateOfBirth: date(1990, 10, 6))

        #expect(athlete.age(asOf: date(2026, 10, 5)) == 35)
        #expect(athlete.age(asOf: date(2026, 10, 6, hour: 0)) == 36)
        #expect(athlete.age(asOf: date(2026, 10, 6, hour: 23)) == 36)
    }

    @Test("the birthday is judged in the athlete's time zone, not UTC")
    func ageFollowsTheAthletesTimeZone() {
        // Born 1990-10-06 in Auckland; at 2026-10-05 23:00 UTC it's already the 6th there.
        let athlete = profile(dateOfBirth: date(1990, 10, 6, hour: 8, in: "Pacific/Auckland"), timeZone: "Pacific/Auckland")
        let instant = date(2026, 10, 5, hour: 23)

        #expect(athlete.age(asOf: instant) == 36)
        #expect(profile(dateOfBirth: date(1990, 10, 6, hour: 8, in: "UTC")).age(asOf: instant) == 35)
    }

    @Test("a birth date in the future gives age zero, not a negative age")
    func futureBirthDateClampsToZero() {
        #expect(profile(dateOfBirth: date(2030, 1, 1)).age(asOf: date(2026, 10, 6)) == 0)
    }

    @Test("the date of birth round-trips through JSON")
    func roundTrips() throws {
        let original = profile(dateOfBirth: date(1990, 10, 6))

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(original))

        #expect(decoded.dateOfBirth == original.dateOfBirth)
        #expect(decoded == original)
    }

    @Test("a profile stored before dateOfBirth existed still decodes, with none")
    func decodesLegacyPayload() throws {
        let original = profile(dateOfBirth: date(1990, 10, 6))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "dateOfBirth")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: legacy)

        #expect(decoded.dateOfBirth == nil)
        #expect(decoded.id == original.id)
    }
}

import Foundation
import Testing
@testable import TrainingCore

@Suite("AthleteProfile identity")
struct AthleteProfileIdentityTests {
    @Test("two profiles built without an explicit id get distinct ids")
    func defaultIDsAreDistinct() {
        let first = AthleteProfile.fixture()
        let second = AthleteProfile.fixture()

        #expect(first.id != second.id)
    }

    @Test("id and name round-trip through JSON encoding, the path a real AthleteProfileRecord relies on")
    func idAndNameRoundTripThroughCoding() throws {
        let original = AthleteProfile.fixture(name: "Alex Athlete")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Alex Athlete")
        #expect(decoded == original)
    }

    @Test("a profile built without an explicit mainSport defaults to running")
    func defaultMainSportIsRunning() {
        #expect(AthleteProfile.fixture().mainSport == .running)
    }

    @Test("a profile persisted before mainSport existed still decodes, defaulting to running")
    func decodingOmittedMainSportDefaultsToRunning() throws {
        let original = AthleteProfile.fixture(name: "Alex Athlete")
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)
        ) as! [String: Any]
        json.removeValue(forKey: "mainSport")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        #expect(decoded.mainSport == .running)
        #expect(decoded.id == original.id)
    }

    @Test("a non-default mainSport round-trips through JSON encoding")
    func nonDefaultMainSportRoundTripsThroughCoding() throws {
        var original = AthleteProfile.fixture(name: "Alex Athlete")
        original.mainSport = .cycling

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        #expect(decoded.mainSport == .cycling)
    }

    @Test("a profile has no usual venue by default, and one set round-trips through JSON encoding")
    func mainVenueRoundTrips() throws {
        #expect(AthleteProfile.fixture().mainVenue == nil)
        var original = AthleteProfile.fixture(name: "Alex Athlete")
        original.mainVenue = .outdoor(.road)

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(original))

        #expect(decoded.mainVenue == .outdoor(.road))
    }

    @Test("a profile whose mainSport was saved as outdoorRunning reads as running outdoors")
    func legacyMainSportVenue() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AthleteProfile.fixture())
        ) as! [String: Any]
        json["mainSport"] = ["outdoorRunning": [String: Any]()]
        json.removeValue(forKey: "mainVenue")

        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.mainSport == .running)
        #expect(decoded.mainVenue == .outdoor(nil))
    }

    @Test("the usual venue only applies to the main sport, and preselects a template's venue when allowed")
    func defaultVenueForSport() {
        var athlete = AthleteProfile.fixture()
        athlete.mainVenue = .indoor(.treadmill)
        #expect(athlete.defaultVenue(for: .running) == .indoor(.treadmill))
        #expect(athlete.defaultVenue(for: .cycling) == nil)

        let open = WorkoutTemplate(name: "Open", sport: .running, parameters: [], blocks: [])
        let outdoorOnly = WorkoutTemplate(name: "Out", sport: .running, venue: .outdoor(nil), parameters: [], blocks: [])
        #expect(open.defaultVenue(for: athlete) == .indoor(.treadmill))
        #expect(outdoorOnly.defaultVenue(for: athlete) == .outdoor(.road))
    }
}

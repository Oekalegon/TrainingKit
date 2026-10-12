import Foundation
import Testing
@testable import TrainingCore

@Suite("Venue")
struct VenueTests {
    @Test("a venue round-trips through JSON, with and without a surface")
    func codingRoundTrip() throws {
        for venue: Venue in [.indoor(nil), .indoor(.treadmill), .outdoor(nil), .outdoor(.offtrail)] {
            let data = try JSONEncoder().encode(venue)
            #expect(try JSONDecoder().decode(Venue.self, from: data) == venue)
        }
    }

    @Test("an unknown surface reads as no surface; an unknown location is an error")
    func unknownValues() throws {
        let surface = Data(#"{"location":"outdoor","surface":"moon"}"#.utf8)
        #expect(try JSONDecoder().decode(Venue.self, from: surface) == .outdoor(nil))
        let location = Data(#"{"location":"underwater"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Venue.self, from: location) }
    }

    @Test("sports encode as they did before, and the old indoor/outdoor running cases read as running with a venue")
    func legacySportMigration() throws {
        #expect(String(decoding: try JSONEncoder().encode(Sport.running), as: UTF8.self) == #"{"running":{}}"#)
        let other = try JSONEncoder().encode(Sport.other("kayak"))
        #expect(try JSONDecoder().decode(Sport.self, from: other) == .other("kayak"))

        let legacy = try JSONDecoder().decode(StoredSport.self, from: Data(#"{"indoorRunning":{}}"#.utf8))
        #expect(legacy.sport == .running)
        #expect(legacy.legacyVenue == .indoor(nil))
        #expect(try JSONDecoder().decode(Sport.self, from: Data(#"{"outdoorRunning":{}}"#.utf8)) == .running)
    }

    @Test("an activity and a workout saved with the old sport cases load with the venue")
    func legacyOwners() throws {
        let activity = Activity(source: .manual, sport: .running, venue: .outdoor(.road), start: Date(timeIntervalSince1970: 0), duration: 60)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
        json["sport"] = ["outdoorRunning": [String: Any]()]
        json["venue"] = nil
        let decoded = try JSONDecoder().decode(Activity.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sport == .running)
        #expect(decoded.venue == .outdoor(nil))

        let workout = StructuredWorkout(name: "W", sport: .running, venue: .indoor(.track), blocks: [])
        #expect(try JSONDecoder().decode(StructuredWorkout.self, from: JSONEncoder().encode(workout)) == workout)
    }
}

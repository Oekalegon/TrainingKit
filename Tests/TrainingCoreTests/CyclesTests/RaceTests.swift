import Foundation
import Testing
@testable import TrainingCore

@Suite("Race")
struct RaceTests {
    @Test("Priorities are primary, secondary and tertiary, in that order")
    func priorityCases() {
        #expect(RacePriority.allCases == [.primary, .secondary, .tertiary])
    }

    @Test("A race round-trips through Codable with its priority")
    func codableRoundTrip() throws {
        let race = Race(name: "City 10K", date: Date(timeIntervalSince1970: 1_800_000_000), priority: .secondary, distanceMeters: 10_000)
        let decoded = try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(race))
        #expect(decoded == race)
    }

    @Test("Priorities decode from their raw string keys, pinning the wire format")
    func decodesRawKeys() throws {
        for (key, expected) in [("primary", RacePriority.primary), ("secondary", .secondary), ("tertiary", .tertiary)] {
            let json = Data("{\"\(key)\":{}}".utf8)
            #expect(try JSONDecoder().decode(RacePriority.self, from: json) == expected)
        }
    }

    @Test("A race's expected load override round-trips, and a stored race without one decodes to nil")
    func expectedLoadOverrideCoding() throws {
        let race = Race(name: "100K", date: Date(timeIntervalSince1970: 1_800_000_000), priority: .primary, distanceMeters: 100_000, expectedLoadOverride: 900)
        #expect(try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(race)) == race)

        var plain = Race(name: "10K", date: race.date, priority: .secondary, distanceMeters: 10_000)
        plain.expectedLoadOverride = nil
        let data = try JSONEncoder().encode(plain)
        #expect(!String(decoding: data, as: UTF8.self).contains("expectedLoadOverride"))
        #expect(try JSONDecoder().decode(Race.self, from: data).expectedLoadOverride == nil)
    }

    @Test("An expected load override that is negative or not finite is invalid")
    func expectedLoadOverrideValidation() throws {
        for load in [-1, Double.infinity, .nan] {
            let race = Race(name: "Bad", date: Date(), priority: .primary, distanceMeters: 10_000, expectedLoadOverride: load)
            #expect(throws: RaceError.invalidExpectedLoad) { try race.validate() }
        }
        try Race(name: "Zero", date: Date(), priority: .primary, distanceMeters: 10_000, expectedLoadOverride: 0).validate()
    }
}

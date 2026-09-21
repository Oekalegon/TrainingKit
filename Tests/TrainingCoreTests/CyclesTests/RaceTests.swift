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
        let race = Race(name: "City 10K", date: Date(timeIntervalSince1970: 1_800_000_000), priority: .secondary)
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
}

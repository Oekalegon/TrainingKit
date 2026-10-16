import Foundation
import Testing
@testable import TrainingCore

@Suite("maxWeeklyVolume and VolumeTarget")
struct MaxWeeklyVolumeTests {
    @Test("defaults to no limit")
    func defaults() {
        #expect(PlanPreferences().maxWeeklyVolume.isEmpty)
    }

    @Test("a target needs a positive, finite amount")
    func invalidAmounts() {
        #expect(VolumeTarget(measure: .distanceMeters, amount: 60_000)?.amount == 60_000)
        for amount in [0, -1, .nan, .infinity, -.infinity] as [Double] {
            #expect(VolumeTarget(measure: .trimp, amount: amount) == nil)
        }
    }

    @Test("round-trips every measure and a sport with an associated value")
    func roundTrip() throws {
        let preferences = PlanPreferences(maxWeeklyVolume: [
            .running: VolumeTarget(measure: .distanceMeters, amount: 60_000)!,
            .cycling: VolumeTarget(measure: .durationSeconds, amount: 18_000)!,
            .other("padel"): VolumeTarget(measure: .trimp, amount: 450)!,
        ])

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: data)

        #expect(decoded == preferences)
    }

    @Test("a payload without maxWeeklyVolume decodes to no limit")
    func legacyPayload() throws {
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data(#"{"runAvailability":{}}"#.utf8))

        #expect(decoded == PlanPreferences())
    }

    @Test("an empty limit is not written")
    func emptyNotEncoded() throws {
        let data = try JSONEncoder().encode(PlanPreferences())
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("maxWeeklyVolume"))
    }

    @Test("invalid and unknown entries are dropped, the valid ones kept")
    func tolerantDecoding() throws {
        let json = """
        {"maxWeeklyVolume":[
          {"sport":{"running":{}},"volume":{"measure":"distanceMeters","amount":50000}},
          {"sport":{"cycling":{}},"volume":{"measure":"distanceMeters","amount":-5}},
          {"sport":{"swimming":{}},"volume":{"measure":"calories","amount":100}},
          {"sport":{"quidditch":{}},"volume":{"measure":"trimp","amount":100}},
          "junk",
          {"sport":{"rowing":{}},"volume":{"measure":"trimp","amount":300}}
        ]}
        """
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data(json.utf8))

        #expect(decoded.maxWeeklyVolume == [
            .running: VolumeTarget(measure: .distanceMeters, amount: 50_000)!,
            .rowing: VolumeTarget(measure: .trimp, amount: 300)!,
        ])
    }

    @Test("a repeated sport keeps the last entry")
    func repeatedSport() throws {
        let json = """
        {"maxWeeklyVolume":[
          {"sport":{"running":{}},"volume":{"measure":"trimp","amount":1}},
          {"sport":{"running":{}},"volume":{"measure":"trimp","amount":2}}
        ]}
        """
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data(json.utf8))

        #expect(decoded.maxWeeklyVolume[.running]?.amount == 2)
    }
}

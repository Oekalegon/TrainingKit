import Foundation
import Testing
@testable import TrainingCore

@Suite("PlanPreferences and RunAvailability")
struct PlanPreferencesTests {
    @Test("defaults to no availability on any day")
    func defaults() {
        let preferences = PlanPreferences()

        #expect(preferences.runAvailability.slots.isEmpty)
        for weekday in Weekday.allCases {
            #expect(preferences.runAvailability[weekday].isEmpty)
        }
    }

    @Test("an empty set removes the weekday and empty entries are dropped on init")
    func emptyEntriesAreNormalised() {
        var availability = RunAvailability(slots: [.monday: [], .tuesday: [.morning]])
        #expect(availability.slots.keys.sorted { $0.rawValue < $1.rawValue } == [.tuesday])

        availability[.tuesday] = []
        #expect(availability.slots.isEmpty)

        availability[.friday] = [.morning, .afternoonEvening]
        #expect(availability[.friday] == [.morning, .afternoonEvening])
    }

    @Test("round-trips through Codable")
    func roundTrip() throws {
        let preferences = PlanPreferences(runAvailability: RunAvailability(slots: [
            .monday: [.morning],
            .saturday: [.morning, .afternoonEvening],
        ]))

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: data)

        #expect(decoded == preferences)
    }

    @Test("an empty availability round-trips")
    func emptyRoundTrip() throws {
        let data = try JSONEncoder().encode(PlanPreferences())
        #expect(try JSONDecoder().decode(PlanPreferences.self, from: data) == PlanPreferences())
    }

    @Test("a payload without runAvailability decodes to the default")
    func legacyPayload() throws {
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data("{}".utf8))

        #expect(decoded == PlanPreferences())
    }

    @Test("a payload without slots decodes to no availability")
    func partialAvailability() throws {
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data("{}".utf8))

        #expect(decoded == RunAvailability())
    }

    @Test("unknown weekdays and slots are ignored")
    func unknownValuesAreIgnored() throws {
        let json = #"{"slots":{"2":["morning","night"],"9":["morning"],"x":["morning"],"3":["night"]}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded == RunAvailability(slots: [.monday: [.morning]]))
    }
}

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

        availability[.friday] = [.morning, .evening]
        #expect(availability[.friday] == [.morning, .evening])
    }

    @Test("round-trips through Codable")
    func roundTrip() throws {
        let preferences = PlanPreferences(runAvailability: RunAvailability(slots: [
            .monday: [.morning],
            .saturday: [.morning, .evening],
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

    @Test("a slot without stored options has the defaults: long run possible, no track")
    func slotOptionDefaults() {
        let availability = RunAvailability(slots: [.saturday: [.morning]])

        #expect(availability[.saturday, .morning] == SlotOptions(longRunPossible: true, trackAvailable: false))
        #expect(availability[.saturday, .morning] == .default)
        #expect(availability.slotOptions.isEmpty)
    }

    @Test("options set on a slot are stored, and assigning the defaults removes them")
    func slotOptionsAreSparse() {
        var availability = RunAvailability(slots: [.tuesday: [.evening]])

        availability[.tuesday, .evening] = SlotOptions(longRunPossible: false, trackAvailable: true)
        #expect(availability[.tuesday, .evening].trackAvailable)
        #expect(!availability[.tuesday, .evening].longRunPossible)

        availability[.tuesday, .evening] = .default
        #expect(availability.slotOptions.isEmpty)
        #expect(RunAvailability(slotOptions: [.monday: [.morning: .default]]).slotOptions.isEmpty)
    }

    @Test("slot options round-trip through Codable")
    func slotOptionsRoundTrip() throws {
        let availability = RunAvailability(
            slots: [.saturday: [.morning, .evening], .tuesday: [.evening]],
            slotOptions: [
                .saturday: [.morning: SlotOptions(longRunPossible: true, trackAvailable: true)],
                .tuesday: [.evening: SlotOptions(longRunPossible: false)],
            ]
        )

        let data = try JSONEncoder().encode(PlanPreferences(runAvailability: availability))
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: data)

        #expect(decoded.runAvailability == availability)
    }

    @Test("availability stored before slot options existed decodes with the default options")
    func legacyAvailabilityWithoutOptions() throws {
        let json = #"{"slots":{"7":["morning","afternoonEvening"]}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded == RunAvailability(slots: [.saturday: [.morning, .afternoon, .evening]]))
        #expect(decoded[.saturday, .morning] == .default)
    }

    @Test("options missing a field get that field's default; unknown weekdays and slots are ignored")
    func partialOptions() throws {
        let json = #"{"slots":{"7":["morning"]},"slotOptions":{"7":{"morning":{"trackAvailable":true},"night":{}},"9":{"morning":{}}}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded[.saturday, .morning] == SlotOptions(longRunPossible: true, trackAvailable: true))
        #expect(decoded.slotOptions.count == 1)
    }

    @Test("the legacy afternoonEvening slot and options key decode to both afternoon and evening")
    func legacyAfternoonEveningDecodesToBoth() throws {
        let json = #"{"slots":{"7":["afternoonEvening"]},"slotOptions":{"7":{"afternoonEvening":{"longRunPossible":false,"trackAvailable":true}}}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        let options = SlotOptions(longRunPossible: false, trackAvailable: true)
        #expect(decoded[.saturday] == [.afternoon, .evening])
        #expect(decoded[.saturday, .afternoon] == options)
        #expect(decoded[.saturday, .evening] == options)
        #expect(decoded[.saturday, .morning] == .default)
    }

    @Test("a legacy slot is written again in the new form and round-trips")
    func legacyRoundTrip() throws {
        let json = #"{"slots":{"7":["morning","afternoonEvening"]},"slotOptions":{"7":{"afternoonEvening":{"trackAvailable":true}}}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        let encoded = try JSONEncoder().encode(decoded)

        #expect(!String(decoding: encoded, as: UTF8.self).contains("afternoonEvening"))
        #expect(try JSONDecoder().decode(RunAvailability.self, from: encoded) == decoded)
    }

    @Test("a legacy slot alongside a new one adds to it, and options under a new name win over the legacy key")
    func legacyAlongsideNewKeys() throws {
        let json = #"{"slots":{"7":["afternoonEvening","evening"],"2":["afternoon"]},"slotOptions":{"7":{"afternoonEvening":{"trackAvailable":true},"evening":{"longRunPossible":false}}}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded[.saturday] == [.afternoon, .evening])
        #expect(decoded[.monday] == [.afternoon])
        #expect(decoded[.saturday, .afternoon] == SlotOptions(longRunPossible: true, trackAvailable: true))
        #expect(decoded[.saturday, .evening] == SlotOptions(longRunPossible: false, trackAvailable: false))
    }

    @Test("a legacy options key without a legacy slot is carried onto both slots")
    func legacyOptionsKeyOnly() throws {
        let json = #"{"slots":{"7":["evening"]},"slotOptions":{"7":{"afternoonEvening":{"trackAvailable":true}}}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded[.saturday] == [.evening])
        #expect(decoded[.saturday, .afternoon].trackAvailable)
        #expect(decoded[.saturday, .evening].trackAvailable)
    }

    @Test("runs per day default to one on a free day and none on a day without slots")
    func runsDefault() {
        let availability = RunAvailability(slots: [.monday: [.morning, .evening]])

        #expect(availability.runs(on: .monday) == 1)
        #expect(availability.runs(on: .tuesday) == 0)
        #expect(availability.runsPerDay.isEmpty)
    }

    @Test("runs are capped at the free slots, but the stored count is kept")
    func runsCappedByFreeSlots() {
        var availability = RunAvailability(slots: [.saturday: [.morning]])
        availability.setRuns(2, on: .saturday)

        #expect(availability.runs(on: .saturday) == 1)
        #expect(availability.runsPerDay[.saturday] == 2)

        availability[.saturday] = [.morning, .evening]
        #expect(availability.runs(on: .saturday) == 2)

        availability[.saturday] = [.morning, .afternoon, .evening]
        availability.setRuns(3, on: .saturday)
        #expect(availability.runs(on: .saturday) == 3)
    }

    @Test("a count of 1 or less is the default and is not stored")
    func runsSparse() {
        var availability = RunAvailability(slots: [.monday: [.morning, .evening]], runsPerDay: [.monday: 1, .tuesday: 0, .friday: -3])
        #expect(availability.runsPerDay.isEmpty)

        availability.setRuns(2, on: .monday)
        availability.setRuns(1, on: .monday)
        #expect(availability.runsPerDay.isEmpty)
    }

    @Test("runs per day round-trip through Codable")
    func runsRoundTrip() throws {
        let availability = RunAvailability(slots: [.saturday: [.morning, .evening]], runsPerDay: [.saturday: 2])

        let data = try JSONEncoder().encode(PlanPreferences(runAvailability: availability))
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: data)

        #expect(decoded.runAvailability == availability)
        #expect(decoded.runAvailability.runs(on: .saturday) == 2)
    }

    @Test("availability stored before runs per day existed decodes to one run a day, and one run writes no field")
    func legacyWithoutRuns() throws {
        let json = #"{"slots":{"7":["morning","evening"]}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded.runs(on: .saturday) == 1)
        #expect(!String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("runsPerDay"))
    }

    @Test("stored counts of 1 or less and unknown weekdays are ignored on decode")
    func runsTolerantDecoding() throws {
        let json = #"{"slots":{"7":["morning","evening"]},"runsPerDay":{"7":2,"2":1,"3":0,"9":2}}"#

        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))

        #expect(decoded.runsPerDay == [.saturday: 2])
    }

    @Test("the spacing override round-trips, is left out when nil and reads below 1 as nil")
    func spacingCoding() throws {
        let preferences = PlanPreferences(minDaysBetweenHardSessions: 3)
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded.minDaysBetweenHardSessions == 3)
        #expect(!String(decoding: try JSONEncoder().encode(PlanPreferences()), as: UTF8.self).contains("minDaysBetweenHardSessions"))
        #expect(PlanPreferences(minDaysBetweenHardSessions: 0).minDaysBetweenHardSessions == nil)
        #expect(try JSONDecoder().decode(PlanPreferences.self, from: Data(#"{"minDaysBetweenHardSessions":-2}"#.utf8)).minDaysBetweenHardSessions == nil)
    }
}

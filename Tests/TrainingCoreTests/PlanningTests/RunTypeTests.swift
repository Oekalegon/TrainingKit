import Foundation
import Testing
@testable import TrainingCore

@Suite("RunType and RunAvailability.dayRunTypes")
struct RunTypeTests {
    private let allDays: [Weekday: Set<DaySlot>] = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, [DaySlot.morning]) })

    @Test("maps each run type to an intensity category and a session type", arguments: [
        (RunType.recovery, IntensityCategory.veryLow, SessionType.recovery),
        (.easy, .low, .easy),
        (.long, .low, .long),
        (.threshold, .high, .tempo),
        (.interval, .high, .interval),
    ])
    func mapping(type: RunType, category: IntensityCategory, session: SessionType) {
        #expect(type.intensityCategory == category)
        #expect(type.sessionType == session)
    }

    @Test("the mapping table covers every run type")
    func mappingIsExhaustive() {
        #expect(RunType.allCases.count == 5)
        #expect(Set(RunType.allCases.map(\.sessionType)).count == 5)
    }

    @Test("defaults to none named, so every running day allows every run type")
    func defaults() {
        let availability = RunAvailability(slots: allDays)
        #expect(availability.dayRunTypes.isEmpty)
        #expect(availability.runTypes(on: .monday) == Set(RunType.allCases))
    }

    @Test("a day allows the types it names plus the types no day names")
    func namedPlusFree() {
        let availability = RunAvailability(slots: allDays, dayRunTypes: [.sunday: [.long], .thursday: [.interval, .easy]])
        #expect(availability.runTypes(on: .tuesday) == [.recovery, .threshold])
        #expect(availability.runTypes(on: .sunday) == [.long, .recovery, .threshold])
        #expect(availability.runTypes(on: .thursday) == [.interval, .easy, .recovery, .threshold])
    }

    @Test("a type named on two days is allowed on both and nowhere else")
    func sameTypeOnTwoDays() {
        let availability = RunAvailability(slots: allDays, dayRunTypes: [.saturday: [.long], .sunday: [.long]])
        #expect(availability.runTypes(on: .saturday).contains(.long))
        #expect(availability.runTypes(on: .sunday).contains(.long))
        #expect(!availability.runTypes(on: .monday).contains(.long))
    }

    @Test("a day without free slots allows nothing, but its names are kept")
    func dayWithoutSlots() {
        var availability = RunAvailability(slots: [.monday: [.morning]], dayRunTypes: [.sunday: [.long]])
        #expect(availability.runTypes(on: .sunday).isEmpty)
        // The long run is still reserved for Sunday, so it is not offered on Monday.
        #expect(!availability.runTypes(on: .monday).contains(.long))
        availability[.sunday] = [.morning]
        #expect(availability.runTypes(on: .sunday).contains(.long))
    }

    @Test("an unnamed day can end up with no types when every type is named elsewhere")
    func fullyNamed() {
        let availability = RunAvailability(slots: allDays, dayRunTypes: [.monday: Set(RunType.allCases)])
        #expect(availability.runTypes(on: .tuesday).isEmpty)
    }

    @Test("an empty set removes the entry")
    func emptySetRemoves() {
        var availability = RunAvailability(slots: allDays, dayRunTypes: [.monday: [], .tuesday: [.long]])
        #expect(availability.dayRunTypes == [.tuesday: [.long]])
        availability.setRunTypes([], on: .tuesday)
        #expect(availability.dayRunTypes.isEmpty)
    }

    @Test("round-trips through Codable, also inside the preferences")
    func roundTrip() throws {
        let availability = RunAvailability(slots: allDays, dayRunTypes: [.sunday: [.long], .thursday: [.interval, .threshold]])
        let data = try JSONEncoder().encode(PlanPreferences(runAvailability: availability))
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: data)
        #expect(decoded.runAvailability == availability)
    }

    @Test("availability stored without dayRunTypes decodes to none named")
    func legacyPayload() throws {
        let json = #"{"slots":{"2":["morning"]},"runsPerDay":{"2":2}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(decoded.dayRunTypes.isEmpty)
        #expect(decoded[.monday] == [.morning])
    }

    @Test("unknown run types, weekdays and empty entries are ignored on decode")
    func tolerantDecode() throws {
        let json = #"{"dayRunTypes":{"1":["long","fartlek"],"2":["fartlek"],"3":[],"99":["easy"],"x":["easy"]}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(decoded.dayRunTypes == [.sunday: [.long]])
    }
}

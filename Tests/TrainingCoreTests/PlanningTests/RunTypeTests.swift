import Foundation
import Testing
@testable import TrainingCore

@Suite("RunType and PlanPreferences.dayRunTypes")
struct RunTypeTests {
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

    @Test("defaults to no run types, so a day allows only recovery and easy runs")
    func defaults() {
        let preferences = PlanPreferences()
        #expect(preferences.dayRunTypes.isEmpty)
        #expect(preferences.runTypes(onDay: 3, microLength: 7) == [.recovery, .easy])
    }

    @Test("several types per day, and empty sets and negative days are dropped")
    func normalisation() {
        var preferences = PlanPreferences(dayRunTypes: [0: [.easy, .long], 1: [], -1: [.easy]])
        #expect(preferences.dayRunTypes == [0: [.easy, .long]])
        #expect(preferences.runTypes(onDay: 0, microLength: 7) == [.easy, .long])

        preferences.setRunTypes([.interval], onDay: 2)
        preferences.setRunTypes([], onDay: 0)
        preferences.setRunTypes([.easy], onDay: -2)
        #expect(preferences.dayRunTypes == [2: [.interval]])
    }

    @Test("a day outside the micro has no run types but is kept; validated drops it")
    func outOfRangeDay() {
        let preferences = PlanPreferences(dayRunTypes: [1: [.threshold], 9: [.long]])
        #expect(preferences.runTypes(onDay: 9, microLength: 7).isEmpty)
        #expect(preferences.runTypes(onDay: 7, microLength: 7).isEmpty)
        #expect(preferences.runTypes(onDay: -1, microLength: 7).isEmpty)
        #expect(preferences.runTypes(onDay: 9, microLength: 10) == [.long])
        #expect(preferences.dayRunTypes[9] == [.long])

        #expect(preferences.validated(microLength: 7).dayRunTypes == [1: [.threshold]])
        #expect(preferences.validated(microLength: 14).dayRunTypes == preferences.dayRunTypes)
    }

    @Test("round-trips through Codable")
    func roundTrip() throws {
        let preferences = PlanPreferences(
            runAvailability: RunAvailability(slots: [.monday: [.morning]]),
            dayRunTypes: [0: [.easy, .recovery], 5: [.long]]
        )
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(PlanPreferences.self, from: data) == preferences)
    }

    @Test("a payload without dayRunTypes decodes to the defaults")
    func legacyPayload() throws {
        let json = #"{"runAvailability":{"slots":{"2":["morning"]}}}"#
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data(json.utf8))
        #expect(decoded.dayRunTypes.isEmpty)
        #expect(decoded.runAvailability[.monday] == [.morning])
    }

    @Test("unknown run types, bad days and empty entries are ignored on decode")
    func tolerantDecode() throws {
        let json = #"{"dayRunTypes":{"0":["easy","fartlek"],"1":["fartlek"],"2":[],"-1":["easy"],"x":["easy"],"3":["long"]}}"#
        let decoded = try JSONDecoder().decode(PlanPreferences.self, from: Data(json.utf8))
        #expect(decoded.dayRunTypes == [0: [.easy], 3: [.long]])
    }
}

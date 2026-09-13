import Testing
@testable import TrainingCore

@Suite("Sport.isSameFamily")
struct SportFamilyTests {
    @Test("A sport is always the same family as itself")
    func sameCaseIsSameFamily() {
        #expect(Sport.running.isSameFamily(as: .running))
        #expect(Sport.other("kayaking").isSameFamily(as: .other("kayaking")))
    }

    @Test("Hiking and walking are the same family")
    func hikingAndWalking() {
        #expect(Sport.hiking.isSameFamily(as: .walking))
        #expect(Sport.walking.isSameFamily(as: .hiking))
    }

    @Test("Plain running is the same family as indoor or outdoor running")
    func plainRunningMatchesEitherVenue() {
        #expect(Sport.running.isSameFamily(as: .indoorRunning))
        #expect(Sport.running.isSameFamily(as: .outdoorRunning))
        #expect(Sport.indoorRunning.isSameFamily(as: .running))
        #expect(Sport.outdoorRunning.isSameFamily(as: .running))
    }

    @Test("Explicit indoor running and explicit outdoor running are NOT the same family")
    func explicitVenuesDisagree() {
        #expect(!Sport.indoorRunning.isSameFamily(as: .outdoorRunning))
        #expect(!Sport.outdoorRunning.isSameFamily(as: .indoorRunning))
    }

    @Test("Unrelated sports are never the same family")
    func unrelatedSports() {
        #expect(!Sport.running.isSameFamily(as: .cycling))
        #expect(!Sport.hiking.isSameFamily(as: .running))
        #expect(!Sport.walking.isSameFamily(as: .indoorRunning))
        #expect(!Sport.other("kayaking").isSameFamily(as: .other("canoeing")))
    }
}

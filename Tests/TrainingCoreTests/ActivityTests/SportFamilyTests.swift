import Testing
@testable import TrainingCore

@Suite("Sport.isSameFamily")
struct SportFamilyTests {
    @Test("A sport is always the same family as itself")
    func sameCaseIsSameFamily() {
        #expect(Sport.running.isSameFamily(as: .running, venue: nil, otherVenue: nil))
        #expect(Sport.other("kayaking").isSameFamily(as: .other("kayaking"), venue: nil, otherVenue: nil))
    }

    @Test("Hiking and walking are the same family")
    func hikingAndWalking() {
        #expect(Sport.hiking.isSameFamily(as: .walking, venue: nil, otherVenue: nil))
        #expect(Sport.walking.isSameFamily(as: .hiking, venue: nil, otherVenue: nil))
    }

    @Test("A run with no venue is the same family as a run at any venue")
    func plainRunningMatchesEitherVenue() {
        #expect(Sport.running.isSameFamily(as: .running, venue: nil, otherVenue: .indoor(.treadmill)))
        #expect(Sport.running.isSameFamily(as: .running, venue: .outdoor(.trail), otherVenue: nil))
    }

    @Test("Indoor and outdoor runs are NOT the same family, whatever the surface")
    func explicitVenuesDisagree() {
        #expect(!Sport.running.isSameFamily(as: .running, venue: .indoor(.track), otherVenue: .outdoor(.track)))
        #expect(!Sport.running.isSameFamily(as: .running, venue: .indoor(nil), otherVenue: .outdoor(.road)))
    }

    @Test("Outdoor runs on different surfaces are the same family")
    func outdoorSurfacesAgree() {
        #expect(Sport.running.isSameFamily(as: .running, venue: .outdoor(.trail), otherVenue: .outdoor(.road)))
        #expect(Sport.running.isSameFamily(as: .running, venue: .indoor(.treadmill), otherVenue: .indoor(.track)))
    }

    @Test("Unrelated sports are never the same family")
    func unrelatedSports() {
        #expect(!Sport.running.isSameFamily(as: .cycling, venue: nil, otherVenue: nil))
        #expect(!Sport.hiking.isSameFamily(as: .running, venue: nil, otherVenue: nil))
        #expect(!Sport.walking.isSameFamily(as: .running, venue: nil, otherVenue: nil))
        #expect(!Sport.other("kayaking").isSameFamily(as: .other("canoeing"), venue: nil, otherVenue: nil))
    }
}

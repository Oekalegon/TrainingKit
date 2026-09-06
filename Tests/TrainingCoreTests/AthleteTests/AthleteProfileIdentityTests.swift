import Foundation
import Testing
@testable import TrainingCore

@Suite("AthleteProfile identity")
struct AthleteProfileIdentityTests {
    @Test("two profiles built without an explicit id get distinct ids")
    func defaultIDsAreDistinct() {
        let first = AthleteProfile.fixture()
        let second = AthleteProfile.fixture()

        #expect(first.id != second.id)
    }

    @Test("id and name round-trip through JSON encoding, the path a real AthleteProfileRecord relies on")
    func idAndNameRoundTripThroughCoding() throws {
        let original = AthleteProfile.fixture(name: "Alex Athlete")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Alex Athlete")
        #expect(decoded == original)
    }
}

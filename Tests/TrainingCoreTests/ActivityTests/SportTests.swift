import Testing
@testable import TrainingCore

@Suite("Sport.otherLabel / otherRawValue")
struct SportTests {
    @Test("otherRawValue recovers the raw value encoded by otherLabel(rawValue:)")
    func otherRawValueRoundTripsThroughOtherLabel() {
        let label = Sport.otherLabel(rawValue: 42)
        let sport = Sport.other(label)

        #expect(sport.otherRawValue == 42)
    }

    @Test("otherRawValue is nil for every non-.other case")
    func otherRawValueIsNilForDirectCases() {
        #expect(Sport.running.otherRawValue == nil)
        #expect(Sport.cycling.otherRawValue == nil)
        #expect(Sport.swimming.otherRawValue == nil)
        #expect(Sport.strength.otherRawValue == nil)
        #expect(Sport.walking.otherRawValue == nil)
        #expect(Sport.rowing.otherRawValue == nil)
    }

    @Test("otherRawValue is nil for a hand-typed .other label that doesn't match the otherLabel(rawValue:) format")
    func otherRawValueIsNilForUnrecognizedLabel() {
        #expect(Sport.other("hand-typed label").otherRawValue == nil)
        #expect(Sport.other("HKWorkoutActivityType(rawValue: not-a-number)").otherRawValue == nil)
    }
}

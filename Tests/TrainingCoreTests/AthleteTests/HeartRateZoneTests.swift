import Testing
@testable import TrainingCore

@Suite("HeartRateZone")
struct HeartRateZoneTests {
    @Test(
        "rawValue matches the zone number it names",
        arguments: [
            (HeartRateZone.recovery, 1),
            (.aerobic, 2),
            (.tempo, 3),
            (.threshold, 4),
            (.anaerobic, 5),
        ]
    )
    func rawValueMatchesZoneNumber(zone: HeartRateZone, expectedNumber: Int) {
        #expect(zone.rawValue == expectedNumber)
    }

    @Test("allCases covers zones 1...5 in ascending order")
    func allCasesCoversZonesInOrder() {
        #expect(HeartRateZone.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
    }

    @Test("an out-of-range zone number has no matching case")
    func outOfRangeZoneNumberHasNoCase() {
        #expect(HeartRateZone(rawValue: 0) == nil)
        #expect(HeartRateZone(rawValue: 6) == nil)
    }
}

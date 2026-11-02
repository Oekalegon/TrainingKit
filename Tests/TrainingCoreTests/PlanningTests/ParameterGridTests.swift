import Testing
@testable import TrainingCore

@Suite("ParameterGrid")
struct ParameterGridTests {
    @Test("the step of a duration grows with the value, and a band's lower bound belongs to the band", arguments: [
        (30.0, 5.0), (59, 5), (60, 30), (299, 30), (300, 60), (599, 60), (600, 300), (5_999, 300), (6_000, 600), (7_200, 600),
    ])
    func durationStep(value: Double, step: Double) {
        #expect(ParameterGrid.step(at: value, unit: .minutes) == step)
    }

    @Test("the step of a distance grows with the value", arguments: [
        (100.0, 50.0), (200, 100), (399, 100), (400, 400), (1_599, 400), (1_600, 800), (2_999, 800), (3_000, 1_000), (9_999, 1_000), (10_000, 5_000), (42_195, 5_000),
    ])
    func distanceStep(value: Double, step: Double) {
        #expect(ParameterGrid.step(at: value, unit: .meters) == step)
    }

    @Test("durations: 5 s under a minute, 30 s under 5 minutes, a minute under 10, 5 minutes under 100, 10 minutes from there")
    func durationValues() {
        #expect(ParameterGrid.values(in: 30...75, unit: .minutes) == [30, 35, 40, 45, 50, 55, 60])
        #expect(ParameterGrid.values(in: 45...150, unit: .minutes) == [45, 50, 55, 60, 90, 120, 150])
        #expect(ParameterGrid.values(in: 240...420, unit: .minutes) == [240, 270, 300, 360, 420])
        #expect(ParameterGrid.values(in: 480...720, unit: .minutes) == [480, 540, 600])
        #expect(ParameterGrid.values(in: 15 * 60...35 * 60, unit: .minutes) == [900, 1_200, 1_500, 1_800, 2_100])
        #expect(ParameterGrid.values(in: 5_400...7_200, unit: .minutes) == [5_400, 5_700, 6_000, 6_600, 7_200])
    }

    @Test("distances change step at the band starts: 1.6 km, 2.4 km, 3 km, 4 km")
    func distanceValues() {
        #expect(ParameterGrid.values(in: 1_200...5_000, unit: .meters) == [1_200, 1_600, 2_400, 3_000, 4_000, 5_000])
        #expect(ParameterGrid.values(in: 100...500, unit: .meters) == [100, 150, 200, 300, 400])
        #expect(ParameterGrid.values(in: 8_000...30_000, unit: .meters) == [8_000, 9_000, 10_000, 15_000, 20_000, 25_000, 30_000])
    }

    @Test("a count moves by one, and a range with no grid value gives its start")
    func countsAndNarrowRanges() {
        #expect(ParameterGrid.values(in: 3...6, unit: .count) == [3, 4, 5, 6])
        #expect(ParameterGrid.values(in: 31...34, unit: .minutes) == [31])
    }

    @Test("snapping goes to the nearest grid value")
    func snapping() {
        #expect(ParameterGrid.snapped(33 * 60, unit: .minutes) == 2_100)
        #expect(ParameterGrid.snapped(1_050, unit: .meters) == 1_200)
    }
}

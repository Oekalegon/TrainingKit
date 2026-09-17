import Foundation
import Testing
@testable import TrainingCore

@Suite("FitnessMetricsCalculator")
struct FitnessMetricsCalculatorTests {
    let calculator = FitnessMetricsCalculator()
    let parameters = LoadModelParameters()

    private func series(loads: [Double]) -> [DayLoad] {
        loads.enumerated().map { index, load in
            DayLoad(day: Date(timeIntervalSince1970: Double(index) * 86400), load: load, isProjected: false)
        }
    }

    @Test("EWMA matches a hand-computed value")
    func ewmaMatchesHandComputation() {
        let loads = [100.0, 50.0, 0.0]
        let metrics = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)

        var expectedCTL = 0.0
        var expectedATL = 0.0
        for load in loads {
            expectedCTL += (load - expectedCTL) / parameters.ctlTimeConstantDays
            expectedATL += (load - expectedATL) / parameters.atlTimeConstantDays
        }

        #expect(abs(metrics.last!.ctl - expectedCTL) < 1e-9)
        #expect(abs(metrics.last!.atl - expectedATL) < 1e-9)
    }

    @Test("a steady load converges to that load")
    func steadyLoadConverges() {
        let steadyLoad = 80.0
        let loads = Array(repeating: steadyLoad, count: 400)
        let metrics = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)

        #expect(abs(metrics.last!.ctl - steadyLoad) < 0.5)
        #expect(abs(metrics.last!.atl - steadyLoad) < 0.5)
    }

    @Test("TSB sign flips after a rest day following sustained load")
    func tsbFlipsAfterRest() {
        // 300 days (~7 CTL time constants) of steady load lets CTL/ATL converge (TSB near
        // zero), then a rest day.
        var loads = Array(repeating: 80.0, count: 300)
        loads.append(0.0) // index 300: rest day
        loads.append(0.0) // index 301: TSB here reflects the rest day's ctl/atl
        let metrics = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)

        let steadyStateTSB = metrics[299].tsb
        let tsbAfterRest = metrics[301].tsb

        #expect(abs(steadyStateTSB) < 1) // near zero at steady state
        #expect(tsbAfterRest > steadyStateTSB) // ATL drops faster than CTL after the rest day
        #expect(tsbAfterRest > 0)
    }

    @Test("monotony is NaN on a perfectly flat week")
    func monotonyNaNOnFlatWeek() {
        let loads = Array(repeating: 50.0, count: 7)
        let metrics = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)

        #expect(metrics.last!.monotony.isNaN)
        #expect(metrics.last!.strain.isNaN)
    }

    @Test("a seed offsets the first day's TSB correctly")
    func seedOffsetsFirstDay() {
        let loads = [50.0]
        let seeded = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: (ctl: 40, atl: 60))

        #expect(seeded.first!.tsb == 40 - 60)
        #expect(seeded.first!.isWarmingUp == false)

        let unseeded = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)
        #expect(unseeded.first!.isWarmingUp == true)
    }

    /// `==` on `Double` treats NaN as unequal to itself, which would make an elementwise
    /// comparison of monotony/strain series (legitimately NaN on day 1, a flat week, etc.) fail
    /// even when both sides agree. This treats NaN-vs-NaN as a match.
    private func sameSequence(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0 == $1 || ($0.isNaN && $1.isNaN) }
    }

    @Test("recentLoads defaults to empty, matching today's always-cold monotony/strain")
    func recentLoadsDefaultsToEmpty() {
        let loads = [50.0, 80.0, 20.0]
        let withDefault = calculator.metrics(for: series(loads: loads), parameters: parameters, seed: nil)
        let withExplicitEmpty = calculator.metrics(
            for: series(loads: loads), parameters: parameters, seed: nil, recentLoads: []
        )
        #expect(sameSequence(withDefault.map(\.monotony), withExplicitEmpty.map(\.monotony)))
        #expect(sameSequence(withDefault.map(\.strain), withExplicitEmpty.map(\.strain)))
    }

    @Test("recentLoads pre-fills the monotony window, matching an unbroken run over the combined series")
    func recentLoadsMatchesUnbrokenRun() {
        let priorLoads = [40.0, 60.0, 50.0]
        let newLoads = [70.0, 30.0]

        // One unbroken run over the combined series is the ground truth: whatever the resumed
        // computation produces for `newLoads` should exactly match the tail of this.
        let combined = calculator.metrics(for: series(loads: priorLoads + newLoads), parameters: parameters, seed: nil)
        let priorTail = Array(priorLoads.suffix(parameters.monotonyWindowDays))

        // Resume from a seed matching combined's state after `priorLoads`, plus the raw loads
        // needed to rebuild the monotony window.
        let seed = (ctl: combined[priorLoads.count - 1].ctl, atl: combined[priorLoads.count - 1].atl)
        let resumed = calculator.metrics(
            for: series(loads: newLoads), parameters: parameters, seed: seed, recentLoads: priorTail
        )

        let expectedTail = combined.suffix(newLoads.count)
        for (resumedDay, expectedDay) in zip(resumed, expectedTail) {
            #expect(abs(resumedDay.ctl - expectedDay.ctl) < 1e-9)
            #expect(abs(resumedDay.atl - expectedDay.atl) < 1e-9)
            #expect(abs(resumedDay.monotony - expectedDay.monotony) < 1e-9 || (resumedDay.monotony.isNaN && expectedDay.monotony.isNaN))
            #expect(abs(resumedDay.strain - expectedDay.strain) < 1e-9 || (resumedDay.strain.isNaN && expectedDay.strain.isNaN))
        }
    }

    @Test("recentLoads longer than monotonyWindowDays is truncated to the trailing window")
    func recentLoadsTruncatedToWindow() {
        let loads = [1.0]
        let exactWindow = Array(repeating: 99.0, count: parameters.monotonyWindowDays)
        let overlong = Array(repeating: 1.0, count: 50) + exactWindow

        let withExactWindow = calculator.metrics(
            for: series(loads: loads), parameters: parameters, seed: nil, recentLoads: exactWindow
        )
        let withOverlong = calculator.metrics(
            for: series(loads: loads), parameters: parameters, seed: nil, recentLoads: overlong
        )

        #expect(withExactWindow.first!.monotony == withOverlong.first!.monotony)
        #expect(withExactWindow.first!.strain == withOverlong.first!.strain)
    }
}

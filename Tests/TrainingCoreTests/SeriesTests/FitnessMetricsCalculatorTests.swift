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
}

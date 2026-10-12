import Foundation
import Testing
@testable import TrainingCore

/// Averaging speed into windows before it is stored (MVP2-146).
@Suite("SpeedSample downsampling")
struct SpeedSampleDownsamplingTests {
    private let base = Date(timeIntervalSince1970: 1_699_920_000)

    private func sample(_ second: Double, _ speed: Double) -> SpeedSample {
        SpeedSample(time: base.addingTimeInterval(second), metersPerSecond: speed)
    }

    @Test("samples in one window become one, at their mean time and speed")
    func windowsAverage() {
        let samples = [sample(0, 2), sample(1, 3), sample(2, 4), sample(3, 3), sample(4, 3), sample(5, 5), sample(6, 7)]

        let result = samples.downsampled(everySeconds: 5)

        #expect(result.count == 2)
        #expect(result[0].time == base.addingTimeInterval(2))
        #expect(result[0].metersPerSecond == 3)
        #expect(result[1].time == base.addingTimeInterval(5.5))
        #expect(result[1].metersPerSecond == 6)
    }

    @Test("a pause stays a gap: a window with no samples produces none, so the integrated distance doesn't bridge it")
    func gapsStay() {
        let samples = [sample(0, 3), sample(1, 3), sample(60, 3), sample(61, 3)]

        let result = samples.downsampled(everySeconds: 5)

        #expect(result.count == 2)
        #expect(result[1].time.timeIntervalSince(result[0].time) > 50)
    }

    @Test("the distance integrated from the averaged samples stays close to the original's")
    func distancePreserved() {
        // One sample a second for ten minutes at a steady 3 m/s, with a +/-1 m/s wobble.
        let samples = (0..<600).map { sample(Double($0), 3 + ($0 % 2 == 0 ? 1.0 : -1.0)) }
        func meters(_ values: [SpeedSample]) -> Double {
            DistanceTrack(speed: values, gapThresholdSeconds: 30).totalMeters
        }

        let original = meters(samples)
        let averaged = meters(samples.downsampled(everySeconds: 5))

        #expect(abs(original - averaged) / original < 0.02)
        #expect(samples.downsampled(everySeconds: 5).count == 120)
    }

    @Test("unordered input is sorted first; a window of zero or less, or too few samples, returns the input")
    func edges() {
        let unordered = [sample(7, 3), sample(0, 1), sample(1, 1)]
        #expect(unordered.downsampled(everySeconds: 5).map(\.metersPerSecond) == [1, 3])
        #expect(unordered.downsampled(everySeconds: 0) == unordered)
        #expect([sample(0, 1)].downsampled(everySeconds: 5) == [sample(0, 1)])
        #expect([SpeedSample]().downsampled(everySeconds: 5).isEmpty)
    }
}

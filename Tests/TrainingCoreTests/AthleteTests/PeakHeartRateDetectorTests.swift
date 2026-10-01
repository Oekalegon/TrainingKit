import Foundation
import Testing
@testable import TrainingCore

@Suite("PeakHeartRateDetector")
struct PeakHeartRateDetectorTests {
    let detector = PeakHeartRateDetector()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// One sample every `interval` seconds with the given bpm values.
    private func samples(_ bpms: [Double], every interval: TimeInterval = 5, from offset: TimeInterval = 0) -> [HeartRateSample] {
        bpms.enumerated().map { index, bpm in
            HeartRateSample(time: start.addingTimeInterval(offset + Double(index) * interval), bpm: bpm)
        }
    }

    @Test("no samples has no peak")
    func empty() {
        #expect(detector.sustainedPeak(in: []) == nil)
    }

    @Test("samples spanning less than the sustain window have no peak")
    func tooShort() {
        #expect(detector.sustainedPeak(in: samples([150, 160], every: 5)) == nil)
    }

    @Test("a value held across the whole window is the peak")
    func heldValue() {
        let peak = detector.sustainedPeak(in: samples([150, 170, 185, 186, 185, 170]))

        #expect(peak?.bpm == 185)
        #expect(peak?.time == start.addingTimeInterval(10))
    }

    @Test("a single-sample spike is ignored")
    func spikeIgnored() {
        let peak = detector.sustainedPeak(in: samples([170, 171, 172, 230, 172, 171, 170]))

        #expect(peak?.bpm == 172)
    }

    @Test("a held value above the plausible maximum is rejected as a sensor fault")
    func implausibleRejected() {
        #expect(detector.sustainedPeak(in: samples([240, 240, 240, 240])) == nil)
    }

    @Test("a stuck, implausible stretch doesn't hide a genuine peak elsewhere in the activity")
    func stuckStretchDoesNotHideGenuinePeak() {
        let genuine = samples([185, 186, 187, 186])
        let stuck = samples([240, 240, 240, 240], from: 600)

        let peak = detector.sustainedPeak(in: genuine + stuck)

        #expect(peak?.bpm == 186)
    }

    @Test("a cadence lock (a jump no heart makes, held for 30 s) is discarded")
    func cadenceLockDiscarded() {
        let peak = detector.sustainedPeak(in: samples([150, 151, 150, 182, 182, 183, 182, 182, 182, 150, 151]))

        #expect(peak?.bpm == 150)
    }

    @Test("a jump with no matching drop is kept, so one misfire can't discard the rest of the workout")
    func unreleasedJumpKept() {
        let peak = detector.sustainedPeak(in: samples([150, 151, 150, 182, 182, 183, 182, 182]))

        #expect(peak?.bpm == 182)
    }

    @Test("a fast but physiological rise (3 bpm/s) is kept")
    func physiologicalRiseKept() {
        let peak = detector.sustainedPeak(in: samples([150, 165, 180, 188, 189, 189, 188]))

        #expect(peak?.bpm == 188)
    }

    @Test("with 1 s sampling, a jump is measured over 5 s, so ordinary sample noise isn't a lock")
    func oneSecondNoiseNotALock() {
        // ±4 bpm alternating noise around 185: 8 bpm/s sample to sample, but flat over 5 s.
        let noisy = (0..<30).map { 185 + ($0 % 2 == 0 ? 4.0 : -4.0) }

        let peak = detector.sustainedPeak(in: samples(noisy, every: 1))

        #expect(peak?.bpm == 181)
    }

    @Test("non-finite and non-positive samples are dropped, not treated as the window minimum")
    func invalidSamplesDropped() {
        let peak = detector.sustainedPeak(in: samples([180, .nan, 0, 181, 182], every: 3))

        #expect(peak?.bpm == 180)
    }

    @Test("a window never spans a gap longer than maximumGapSeconds")
    func gapSplitsRuns() {
        // Two isolated readings 60 s apart would form a 10 s window if the gap were ignored.
        let peak = detector.sustainedPeak(in: samples([190, 190], every: 60))

        #expect(peak == nil)
    }

    @Test("the best run wins when there are several")
    func bestRunWins() {
        let first = samples([160, 161, 162, 161])
        let second = samples([175, 176, 177, 176], from: 600)

        let peak = detector.sustainedPeak(in: first + second)

        #expect(peak?.bpm == 176)
    }

    @Test("sample order doesn't matter")
    func orderIndependent() {
        let ordered = samples([150, 170, 185, 186, 185, 170])

        #expect(detector.sustainedPeak(in: ordered.reversed()) == detector.sustainedPeak(in: ordered))
    }

    @Test("with seeded sensor noise, the held peak stays within a few bpm of the true effort")
    func noisyIntervalsStayClose() {
        // 1 km-style intervals: four 3-minute efforts settling near 190 bpm.
        let effort: [SimulatedHeartRate.Effort] = Array(
            repeating: [(seconds: 180, bpm: 190), (seconds: 90, bpm: 130)], count: 4
        ).flatMap { $0 }
        for seed in UInt64(1)...20 {
            let noisy = SimulatedHeartRate.samples(
                effort, start: start, noise: SimulatedHeartRate.WhiteNoise(sigma: 3, seed: seed)
            )

            let peak = detector.sustainedPeak(in: noisy)

            #expect(peak.map { abs($0.bpm - 190) <= 6 } == true, "seed \(seed): \(String(describing: peak?.bpm))")
        }
    }

    @Test("out-of-range parameters are clamped")
    func parametersClamped() {
        let clamped = PeakHeartRateDetector(
            sustainSeconds: -5, maximumGapSeconds: .nan, plausibleMaximumBPM: 20, maximumRiseBPMPerSecond: 0
        )

        #expect(clamped.sustainSeconds == 1)
        #expect(clamped.maximumGapSeconds == 15)
        #expect(clamped.plausibleMaximumBPM == 100)
        #expect(clamped.maximumRiseBPMPerSecond == 1)
    }
}

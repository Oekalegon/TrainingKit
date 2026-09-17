import Foundation
import Testing
@testable import TrainingCore

@Suite("ExponentialTRIMPCalculator")
struct ExponentialTRIMPCalculatorTests {
    let athlete = AthleteProfile.fixture()
    let calculator = ExponentialTRIMPCalculator()

    private func activity(heartRate: [HeartRateSample], duration: TimeInterval = 1800) -> Activity {
        Activity(source: .manual, sport: .running, start: Date(timeIntervalSince1970: 0), duration: duration, heartRate: heartRate)
    }

    private func samples(bpm: Double, everySeconds: TimeInterval, count: Int) -> [HeartRateSample] {
        (0..<count).map { HeartRateSample(time: Date(timeIntervalSince1970: Double($0) * everySeconds), bpm: bpm) }
    }

    @Test("constant heart rate reproduces the closed-form value exactly")
    func constantHeartRateClosedForm() throws {
        let bpm = 120.0 // ratio = (120-50)/(190-50) = 0.5
        let minutes = 30.0
        let hr = samples(bpm: bpm, everySeconds: 60, count: Int(minutes) + 1)

        let load = try calculator.load(for: activity(heartRate: hr), athlete: athlete)

        let ratio = 0.5
        let expected = minutes * ratio * (0.64 * exp(1.92 * ratio))
        #expect(abs(load.value - expected) < 1e-9)
    }

    @Test("a hard/easy split scores higher than the flat average-equivalent")
    func convexityOfIntensity() throws {
        let easyBPM = 110.0
        let hardBPM = 160.0
        let averageBPM = (easyBPM + hardBPM) / 2

        var splitSamples = samples(bpm: easyBPM, everySeconds: 60, count: 16)
        let hardStart = 15 * 60.0
        splitSamples += (0..<16).map {
            HeartRateSample(time: Date(timeIntervalSince1970: hardStart + Double($0) * 60), bpm: hardBPM)
        }
        let flatSamples = samples(bpm: averageBPM, everySeconds: 60, count: 31)

        let splitLoad = try calculator.load(for: activity(heartRate: splitSamples), athlete: athlete)
        let flatLoad = try calculator.load(for: activity(heartRate: flatSamples), athlete: athlete)

        #expect(splitLoad.value > flatLoad.value)
    }

    @Test("an empty heart-rate stream throws noHeartRateData")
    func emptyStreamThrows() {
        #expect(throws: LoadError.noHeartRateData) {
            try calculator.load(for: activity(heartRate: []), athlete: athlete)
        }
    }

    @Test("NaN or negative bpm is rejected")
    func invalidSamplesRejected() {
        let nanSample = [HeartRateSample(time: Date(), bpm: .nan)]
        let negativeSample = [HeartRateSample(time: Date(), bpm: -10)]

        #expect(throws: LoadError.self) {
            try calculator.load(for: activity(heartRate: nanSample), athlete: athlete)
        }
        #expect(throws: LoadError.self) {
            try calculator.load(for: activity(heartRate: negativeSample), athlete: athlete)
        }
    }

    @Test("gaps longer than the threshold are excluded rather than bridged")
    func gapHandling() throws {
        let clusterA = samples(bpm: 130, everySeconds: 60, count: 3) // 0, 60, 120s
        let clusterB = (0..<3).map {
            HeartRateSample(time: Date(timeIntervalSince1970: 600 + Double($0) * 60), bpm: 150) // gap of 480s > 60s threshold
        }

        let combinedLoad = try calculator.load(for: activity(heartRate: clusterA + clusterB), athlete: athlete)
        let onlyALoad = try calculator.load(for: activity(heartRate: clusterA), athlete: athlete)
        let onlyBLoad = try calculator.load(for: activity(heartRate: clusterB), athlete: athlete)

        #expect(abs(combinedLoad.value - (onlyALoad.value + onlyBLoad.value)) < 1e-9)
    }
}

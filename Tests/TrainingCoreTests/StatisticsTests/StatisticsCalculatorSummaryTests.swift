import Foundation
import Testing
@testable import TrainingCore

@Suite("StatisticsCalculator.summary")
struct StatisticsCalculatorSummaryTests {
    let athlete = AthleteProfile.fixture() // resting 50, max 190 -> ratio = (bpm-50)/140

    private func activity(heartRate: [HeartRateSample], distanceMeters: Double? = nil, duration: TimeInterval = 1800) -> Activity {
        Activity(source: .manual, sport: .running, start: Date(timeIntervalSince1970: 0), duration: duration, distanceMeters: distanceMeters, heartRate: heartRate)
    }

    @Test("a sample pair crossing a zone boundary halfway splits time proportionally")
    func zoneBoundarySplit() {
        // ratio 0.65 (mid Z2) -> bpm 141, ratio 0.75 (mid Z3) -> bpm 155; the Z2/Z3 boundary at
        // ratio 0.70 is crossed exactly halfway through the 600-second segment.
        let samples = [
            HeartRateSample(time: Date(timeIntervalSince1970: 0), bpm: 141),
            HeartRateSample(time: Date(timeIntervalSince1970: 600), bpm: 155),
        ]
        let calculator = StatisticsCalculator(gapThresholdSeconds: 700)

        let summary = calculator.summary(for: activity(heartRate: samples), athlete: athlete)

        #expect(abs(summary.timeInZone.seconds[2]! - 300) < 1e-9)
        #expect(abs(summary.timeInZone.seconds[3]! - 300) < 1e-9)
    }

    @Test("time in zone total equals moving time minus gaps")
    func totalEqualsMovingTimeMinusGaps() {
        let clusterA = (0..<3).map { HeartRateSample(time: Date(timeIntervalSince1970: Double($0) * 60), bpm: 130) }
        let clusterB = (0..<3).map { HeartRateSample(time: Date(timeIntervalSince1970: 600 + Double($0) * 60), bpm: 150) }
        let calculator = StatisticsCalculator()

        let summary = calculator.summary(for: activity(heartRate: clusterA + clusterB), athlete: athlete)

        // Two 60s segments within each cluster; the 480s gap between clusters is excluded.
        #expect(abs(summary.timeInZone.total - 240) < 1e-9)
    }

    @Test("average heart rate and distance pass through from the activity")
    func passthroughFields() {
        let samples = [
            HeartRateSample(time: Date(timeIntervalSince1970: 0), bpm: 120),
            HeartRateSample(time: Date(timeIntervalSince1970: 60), bpm: 140),
        ]
        let calculator = StatisticsCalculator()

        let summary = calculator.summary(for: activity(heartRate: samples, distanceMeters: 5000, duration: 1800), athlete: athlete)

        #expect(summary.averageHeartRateBPM == 130)
        #expect(summary.distanceMeters == 5000)
        #expect(summary.movingTime == 1800)
    }

    @Test("an activity with no heart-rate data reports empty time in zone")
    func noHeartRateData() {
        let calculator = StatisticsCalculator()

        let summary = calculator.summary(for: activity(heartRate: []), athlete: athlete)

        #expect(summary.timeInZone.total == 0)
        #expect(summary.averageHeartRateBPM == nil)
    }
}

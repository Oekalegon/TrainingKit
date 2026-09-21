import Foundation
@testable import TrainingCore

/// Heart rate simulated as a first-order response to a piecewise-constant effort, with a little
/// deterministic jitter.
///
/// The default time constant (25 s) is deliberately different from the classifiers' default
/// correction (30 s), so tests exercise the lag correction rather than mirror it.
enum SimulatedHeartRate {
    typealias Effort = (seconds: Double, bpm: Double)

    /// A sample every 5 s, beginning at `offset` seconds after `start`, from a resting 60 bpm.
    static func samples(_ profile: [Effort], start: Date, offset: TimeInterval = 0, lag: Double = 25) -> [HeartRateSample] {
        var result: [HeartRateSample] = []
        var heartRate = 60.0
        var second = 0
        let decay = 1 - exp(-1 / lag)
        for effort in profile {
            for _ in 0..<Int(effort.seconds) {
                heartRate += (effort.bpm - heartRate) * decay
                if second % 5 == 0 {
                    let jitter = 1.5 * sin(Double(second) * 0.7)
                    result.append(HeartRateSample(time: start.addingTimeInterval(offset + Double(second)), bpm: heartRate + jitter))
                }
                second += 1
            }
        }
        return result
    }
}

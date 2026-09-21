import Foundation
@testable import TrainingCore

/// Heart rate simulated as a first-order response to a piecewise-constant effort, with a little
/// deterministic jitter and, optionally, white sensor noise.
///
/// The default time constant (25 s) is deliberately different from the classifiers' default
/// correction (30 s), so tests exercise the lag correction rather than mirror it.
enum SimulatedHeartRate {
    typealias Effort = (seconds: Double, bpm: Double)

    /// White Gaussian noise from a seeded generator, so a noise test is reproducible and can be run
    /// across many seeds.
    struct WhiteNoise {
        private var state: UInt64
        let sigma: Double

        init(sigma: Double, seed: UInt64) {
            self.sigma = sigma
            self.state = seed
        }

        private mutating func nextUniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }

        /// Box–Muller.
        mutating func next() -> Double {
            let u1 = max(nextUniform(), 1e-12)
            let u2 = nextUniform()
            return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// A sample every 5 s, beginning at `offset` seconds after `start`, from a resting 60 bpm.
    ///
    /// - Parameter noise: Added to every sample on top of the deterministic jitter — wrist optical
    ///   sensors are noisy at every frequency, which a slow sinusoid isn't.
    static func samples(
        _ profile: [Effort], start: Date, offset: TimeInterval = 0, lag: Double = 25, noise: WhiteNoise? = nil
    ) -> [HeartRateSample] {
        var noise = noise
        var result: [HeartRateSample] = []
        var heartRate = 60.0
        var second = 0
        let decay = 1 - exp(-1 / lag)
        for effort in profile {
            for _ in 0..<Int(effort.seconds) {
                heartRate += (effort.bpm - heartRate) * decay
                if second % 5 == 0 {
                    let jitter = 1.5 * sin(Double(second) * 0.7)
                    let sensorNoise = noise?.next() ?? 0
                    result.append(HeartRateSample(
                        time: start.addingTimeInterval(offset + Double(second)), bpm: heartRate + jitter + sensorNoise
                    ))
                }
                second += 1
            }
        }
        return result
    }
}

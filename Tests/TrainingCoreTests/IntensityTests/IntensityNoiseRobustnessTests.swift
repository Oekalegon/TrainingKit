import Foundation
import Testing
@testable import TrainingCore

/// The classifiers on heart rate with broadband sensor noise, across 20 seeds each.
///
/// The lag correction differentiates the heart rate, which amplifies noise, so these cases guard
/// against noise being read as effort (an easy run credited as tempo) and against noise breaking
/// up a genuinely sustained effort (an easy run read as recovery).
///
/// With the fixture athlete (Karvonen, resting 50 / max 190) the zones are: Z1 120–134 bpm,
/// Z2 134–148, Z3 148–162, Z4 162–176, Z5 176–190.
@Suite("Intensity classification under sensor noise")
struct IntensityNoiseRobustnessTests {
    private let athlete = AthleteProfile.fixture()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let seeds: [UInt64] = Array(1...20)

    private typealias Effort = SimulatedHeartRate.Effort

    private func activity(_ profile: [Effort], sigma: Double, seed: UInt64) -> Activity {
        Activity(
            source: .testing, sport: .running, start: start,
            duration: profile.reduce(0) { $0 + $1.seconds },
            heartRate: SimulatedHeartRate.samples(
                profile, start: start, noise: SimulatedHeartRate.WhiteNoise(sigma: sigma, seed: seed)
            )
        )
    }

    private func categories(_ profile: [Effort], sigma: Double) -> [IntensityCategory] {
        seeds.compactMap { seed in
            PerformedIntensityClassifier().assess(activity(profile, sigma: sigma, seed: seed), athlete: athlete)?.category
        }
    }

    @Test("a steady zone 2 run stays low at 5 bpm of sensor noise, not very low")
    func steadyEasyRunSurvivesNoise() {
        #expect(categories([(3600, 140)], sigma: 5).allSatisfy { $0 == .low })
    }

    @Test("a steady zone 1 recovery run stays very low at 5 bpm of sensor noise")
    func steadyRecoveryRunSurvivesNoise() {
        #expect(categories([(2700, 125)], sigma: 5).allSatisfy { $0 == .veryLow })
    }

    @Test("a steady run just under zone 3 is not read as tempo at 5 bpm of sensor noise")
    func noiseIsNotReadAsTempo() {
        #expect(categories([(3600, 146)], sigma: 5).allSatisfy { $0 == .low })
    }

    @Test("a genuine tempo run is still medium at 3 bpm of sensor noise")
    func tempoSurvivesNoise() {
        let profile: [Effort] = [(600, 130), (1800, 156), (600, 125)]
        #expect(categories(profile, sigma: 3).allSatisfy { $0 == .medium })
    }

    // MARK: - Plan-guided verification

    private var tempoPlan: StructuredWorkout {
        StructuredWorkout(name: "Tempo", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(3))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(600), target: .heartRateZone(1))]),
        ])
    }

    private func guided(tempoBPM: Double, sigma: Double) -> [IntensityCategory] {
        seeds.map { seed in
            let run = activity([(600, 130), (1800, tempoBPM), (600, 125)], sigma: sigma, seed: seed)
            return PlanGuidedIntensityClassifier().assess(run, workout: tempoPlan, athlete: athlete).category
        }
    }

    @Test("a planned tempo run 4 bpm below zone 3 is not credited as tempo, at 3 bpm of sensor noise")
    func tooEasyTempoIsNotCredited() {
        #expect(guided(tempoBPM: 144, sigma: 3).allSatisfy { $0 == .low })
    }

    @Test("a planned tempo run in zone 3 is credited at 3 bpm of sensor noise")
    func genuineTempoIsCredited() {
        #expect(guided(tempoBPM: 152, sigma: 3).allSatisfy { $0 == .medium })
    }
}

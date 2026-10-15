import Foundation
import Testing
@testable import TrainingCore

@Suite("WorkoutDurationEstimator")
struct WorkoutDurationEstimatorTests {
    let athlete = AthleteProfile.fixture()
    let estimator = WorkoutDurationEstimator()

    private func duration(of target: IntensityTarget?, athlete: AthleteProfile) -> TimeInterval {
        estimator.duration(for: WorkoutStep(kind: .work, goal: .distance(5000), target: target), athlete: athlete)
    }

    @Test("a distance step with no target is paced at zone 3")
    func noTargetIsZoneThree() {
        #expect(abs(duration(of: nil, athlete: athlete) - athlete.paceModel.duration(forMeters: 5000, atZone: 3)) < 0.001)
    }

    @Test("a distance step with a pace or power target is paced at zone 4, as the projector assumes")
    func paceAndPowerTargetsAreZoneFour() {
        let expected = athlete.paceModel.duration(forMeters: 5000, atZone: 4)
        #expect(abs(duration(of: .pace(240...250), athlete: athlete) - expected) < 0.001)
        #expect(abs(duration(of: .power(200...220), athlete: athlete) - expected) < 0.001)
    }

    @Test("a heart-rate zone target is paced at that zone")
    func zoneTargetIsThatZone() {
        #expect(abs(duration(of: .heartRateZone(2), athlete: athlete) - athlete.paceModel.duration(forMeters: 5000, atZone: 2)) < 0.001)
    }

    @Test("an athlete without zone settings falls back to the same zones")
    func noZoneSettingsFallsBack() {
        var bare = athlete
        bare.heartRateZoneHistory = []
        #expect(abs(duration(of: nil, athlete: bare) - bare.paceModel.duration(forMeters: 5000, atZone: 3)) < 0.001)
        #expect(abs(duration(of: .pace(240...250), athlete: bare) - bare.paceModel.duration(forMeters: 5000, atZone: 4)) < 0.001)
    }

    @Test("HeartRateZoneModel.zone(for:) agrees with the zone intensityRatio falls in")
    func zoneAgreesWithIntensityRatio() throws {
        let model = HeartRateZoneModel(settings: try #require(athlete.currentHeartRateZoneSettings))
        #expect(model.zone(for: nil) == 3)
        #expect(model.zone(for: .pace(240...250)) == 4)
        #expect(model.zone(for: .rpe(2)) == 1)
    }

    @Test("a method that can't resolve its zones, an out-of-range zone and a heart-rate range all resolve consistently")
    func unusualTargetsResolveConsistently() throws {
        let unresolvable = AthleteProfile.fixture(lactateThresholdHeartRateBPM: nil, zoneMethod: .lactateThreshold)
        #expect(abs(duration(of: .pace(240...250), athlete: unresolvable) - unresolvable.paceModel.duration(forMeters: 5000, atZone: 4)) < 0.001)

        let model = HeartRateZoneModel(settings: try #require(athlete.currentHeartRateZoneSettings))
        #expect(model.zone(for: .heartRateZone(7)) == 3)
        // 130–150 bpm at rest 50 / max 190 → ratio ≈ 0.64 → zone 2 under Karvonen.
        let range = IntensityTarget.heartRateRange(130, 150)
        #expect(model.zone(for: range) == 2)
        #expect(abs(duration(of: range, athlete: athlete) - athlete.paceModel.duration(forMeters: 5000, atZone: model.zone(for: range))) < 0.001)
    }
}

import Foundation
import Testing
@testable import TrainingCore

/// Heart rate is simulated by ``SimulatedHeartRate``.
///
/// With the fixture athlete (Karvonen, resting 50 / max 190) the zones are: Z1 120–134 bpm,
/// Z2 134–148, Z3 148–162, Z4 162–176, Z5 176–190.
@Suite("PerformedIntensityClassifier")
struct PerformedIntensityClassifierTests {
    private let classifier = PerformedIntensityClassifier()
    private let athlete = AthleteProfile.fixture()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private typealias Effort = SimulatedHeartRate.Effort

    private func minutes(_ minutes: Double, _ bpm: Double) -> Effort {
        (minutes * 60, bpm)
    }

    private func samples(_ profile: [Effort], offset: TimeInterval = 0) -> [HeartRateSample] {
        SimulatedHeartRate.samples(profile, start: start, offset: offset)
    }

    private func activity(_ profile: [Effort]) -> Activity {
        Activity(
            source: .testing,
            sport: .running,
            start: start,
            duration: profile.reduce(0) { $0 + $1.seconds },
            heartRate: samples(profile)
        )
    }

    private func category(_ profile: [Effort], classifier: PerformedIntensityClassifier? = nil) -> IntensityCategory? {
        (classifier ?? self.classifier).assess(activity(profile), athlete: athlete)?.category
    }

    @Test("a steady 60 minute easy run in zone 2 is low, measured, with medium confidence")
    func easyRunIsLow() throws {
        let result = try #require(classifier.assess(activity([minutes(60, 140)]), athlete: athlete))

        #expect(result.category == .low)
        #expect(result.source == .measured)
        #expect(result.confidence == .medium)
    }

    @Test("a recovery run in zone 1 is very low")
    func recoveryRunIsVeryLow() {
        #expect(category([minutes(45, 125)]) == .veryLow)
    }

    @Test("brief drifts into zone 3 on an easy run are ignored")
    func briefZoneThreeBlipsAreIgnored() {
        let profile = [
            minutes(20, 140), (30, 156), minutes(10, 140), (30, 156), minutes(10, 140), (30, 156), minutes(19, 140),
        ]

        #expect(category(profile) == .low)
    }

    @Test("many short excursions do not add up to hard time")
    func manyShortExcursionsAreIgnored() throws {
        // 30 excursions of 30 s in zone 4 would total 15 minutes — enough for high — if each counted.
        var profile: [Effort] = []
        for _ in 0..<30 {
            profile += [(170, 140), (30, 168)]
        }

        let result = try #require(classifier.assess(activity(profile), athlete: athlete))

        #expect(result.category == .low)
        #expect(result.hardSeconds == 0)
    }

    @Test("a single sensor spike does not change the category")
    func sensorSpikeIsIgnored() {
        let profile = [minutes(30, 140), (10, 185), minutes(30, 140)]

        #expect(category(profile) == .low)
    }

    @Test("a continuous tempo run in zone 3 is medium")
    func tempoRunIsMedium() {
        #expect(category([minutes(10, 130), minutes(30, 155), minutes(10, 125)]) == .medium)
    }

    @Test("a continuous threshold run in zone 4 is high")
    func thresholdRunIsHigh() {
        #expect(category([minutes(10, 130), minutes(20, 170), minutes(10, 125)]) == .high)
    }

    @Test("5×3 minute intervals with 2 minute recoveries are high, and hard time is close to the true 15 minutes")
    func intervalsAreHigh() throws {
        var profile = [minutes(10, 130)]
        for _ in 0..<5 {
            profile += [minutes(3, 172), minutes(2, 125)]
        }
        profile.append(minutes(10, 125))

        let result = try #require(classifier.assess(activity(profile), athlete: athlete))

        #expect(result.category == .high)
        #expect(abs(result.hardSeconds - 900) < 900 * 0.15)
    }

    @Test("correcting for heart-rate lag recovers hard time that the raw heart rate under-counts")
    func lagCorrectionRecoversHardTime() throws {
        var profile = [minutes(10, 130)]
        for _ in 0..<5 {
            profile += [minutes(3, 172), minutes(2, 125)]
        }
        let run = activity(profile)
        let uncorrected = PerformedIntensityClassifier(parameters: IntensityClassifierParameters(heartRateLagSeconds: 0))

        let raw = try #require(uncorrected.assess(run, athlete: athlete))
        let corrected = try #require(classifier.assess(run, athlete: athlete))

        #expect(raw.hardSeconds < corrected.hardSeconds)
        #expect(raw.hardSeconds < 900 * 0.9)
    }

    @Test("a single 3 minute hill in zone 4 within a 60 minute run stays low")
    func singleHillStaysLow() {
        #expect(category([minutes(30, 140), minutes(3, 170), minutes(27, 140)]) == .low)
    }

    @Test("a 2 hour long run with 12 minutes at tempo stays low")
    func longRunWithBriefTempoIsLow() {
        #expect(category([minutes(108, 140), minutes(12, 155)]) == .low)
    }

    @Test("a 90 minute run with a 20 minute fast finish is medium")
    func fastFinishIsMedium() {
        #expect(category([minutes(70, 140), minutes(20, 155)]) == .medium)
    }

    @Test("a pause longer than the gap threshold is excluded from the session's time")
    func pauseIsExcluded() throws {
        let first = samples([minutes(30, 140)])
        let second = samples([minutes(30, 140)], offset: 50 * 60)
        let run = Activity(source: .testing, sport: .running, start: start, duration: 80 * 60, heartRate: first + second)

        let result = try #require(classifier.assess(run, athlete: athlete))

        #expect(result.category == .low)
        // 60 of the 80 minutes have heart-rate data.
        #expect(result.confidence == .medium)
    }

    @Test("samples covering under half of the activity give low confidence")
    func sparseCoverageLowersConfidence() throws {
        let run = Activity(
            source: .testing, sport: .running, start: start, duration: 60 * 60, heartRate: samples([minutes(20, 140)])
        )

        #expect(try #require(classifier.assess(run, athlete: athlete)).confidence == .low)
    }

    @Test("without heart rate, perceived exertion gives a low-confidence category")
    func exertionFallback() throws {
        func assessed(_ exertion: Int?) -> IntensityAssessment? {
            let run = Activity(source: .manual, sport: .running, start: start, duration: 1800, perceivedExertion: exertion)
            return classifier.assess(run, athlete: athlete)
        }

        #expect(assessed(1)?.category == .veryLow)
        #expect(assessed(4)?.category == .low)
        #expect(assessed(6)?.category == .medium)
        #expect(assessed(8)?.category == .high)
        #expect(assessed(8)?.confidence == .low)
        #expect(assessed(nil) == nil)
    }

    @Test("without recorded zone settings, heart rate is unusable and exertion is used if present")
    func noZoneSettingsFallsBack() {
        let bareAthlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )
        var run = activity([minutes(30, 140)])

        #expect(classifier.assess(run, athlete: bareAthlete) == nil)

        run.perceivedExertion = 3
        #expect(classifier.assess(run, athlete: bareAthlete)?.category == .low)
    }

    @Test("a single heart-rate sample is not enough to classify")
    func singleSampleIsNotEnough() {
        let run = Activity(
            source: .testing, sport: .running, start: start, duration: 600,
            heartRate: [HeartRateSample(time: start, bpm: 150)]
        )

        #expect(classifier.assess(run, athlete: athlete) == nil)
    }

    @Test("samples that are NaN, zero or negative are dropped, so they neither crash nor change the result")
    func invalidSamplesAreDropped() throws {
        var samples = self.samples([minutes(30, 140)])
        for index in stride(from: 40, to: 300, by: 37) {
            samples[index] = HeartRateSample(time: samples[index].time, bpm: [.nan, 0, -10, .infinity][index % 4])
        }
        let run = Activity(source: .testing, sport: .running, start: start, duration: 1800, heartRate: samples)

        let result = try #require(classifier.assess(run, athlete: athlete))

        #expect(result.category == .low)
        #expect(result.hardSeconds == 0)
        #expect(result.moderateSeconds == 0)
    }

    @Test("a run whose samples are all invalid falls back to exertion, or nothing")
    func allInvalidSamples() {
        let samples = (0..<100).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: .nan) }
        var run = Activity(source: .testing, sport: .running, start: start, duration: 500, heartRate: samples)

        #expect(classifier.assess(run, athlete: athlete) == nil)

        run.perceivedExertion = 7
        #expect(classifier.assess(run, athlete: athlete)?.category == .high)
    }

    @Test("time in zone is the run's real length, not one grid step longer")
    func totalsAreNotOverCounted() throws {
        // A perfectly steady zone 3 heart rate for exactly 10 minutes: 121 samples, 120 intervals.
        let samples = (0...120).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 155) }
        let run = Activity(source: .testing, sport: .running, start: start, duration: 600, heartRate: samples)
        let noLag = PerformedIntensityClassifier(parameters: IntensityClassifierParameters(heartRateLagSeconds: 0))

        let result = try #require(noLag.assess(run, athlete: athlete))

        #expect(result.moderateSeconds == 600)
    }
}

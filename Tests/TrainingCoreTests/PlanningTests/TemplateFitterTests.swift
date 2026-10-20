import Foundation
import Testing
@testable import TrainingCore

@Suite("TemplateAnalysis")
struct TemplateAnalysisTests {
    let athlete = AthleteProfile.fixture()

    @Test("interval templates report the work lengths their parameters reach")
    func intervalWorkLengths() throws {
        #expect(try BuiltInWorkoutTemplates.shortIntervalRun.analysis(athlete: athlete).workLength == 30...120)
        #expect(try BuiltInWorkoutTemplates.longIntervalRun.analysis(athlete: athlete).workLength == 180...300)
        #expect(try BuiltInWorkoutTemplates.cruiseIntervalRun.analysis(athlete: athlete).workLength == 300...900)
        #expect(try BuiltInWorkoutTemplates.fartlekZone4.analysis(athlete: athlete).workLength == 60...300)
        // Zone 5 efforts of 30-120 s and Zone 4 of 90-360 s, around a fixed 10-minute Zone 3 run.
        #expect(try BuiltInWorkoutTemplates.mixedIntervalRun.analysis(athlete: athlete).workLength == 30...600)
    }

    @Test("a distance-based effort is timed with the pace model")
    func distanceWorkLength() throws {
        let analysis = try BuiltInWorkoutTemplates.shortIntervalRunTrack.analysis(athlete: athlete)
        let pace = athlete.paceModel
        #expect(analysis.workLength == pace.duration(forMeters: 50, atZone: 5)...pace.duration(forMeters: 800, atZone: 5))
    }

    @Test("counts, work time and duration cover the repetitions range")
    func countsAndDurations() throws {
        let analysis = try BuiltInWorkoutTemplates.longIntervalRun.analysis(athlete: athlete)
        #expect(analysis.workCount == 3...8)
        let workSeconds: ClosedRange<TimeInterval> = 540...2400
        #expect(analysis.workSeconds == workSeconds)
        // 15 minutes of warmup, ramp-in and cooldown around reps x (work + rest).
        let shortest: TimeInterval = 900 + 3 * 300
        let longest: TimeInterval = 900 + 8 * 540
        #expect(analysis.duration == shortest...longest)
    }

    @Test("easy and long templates have no hard work; the tempo run's effort is one hard step")
    func easyHasNoHardWork() throws {
        let easy = try BuiltInWorkoutTemplates.easyRun.analysis(athlete: athlete)
        #expect(!easy.hasHardWork && easy.workLength == nil && easy.workCount == 0...0)
        let easyDuration: ClosedRange<TimeInterval> = 1500...4200
        #expect(easy.duration == easyDuration)
        let tempo = try BuiltInWorkoutTemplates.tempoRun.analysis(athlete: athlete)
        let tempoWork: ClosedRange<TimeInterval> = 900...2700
        #expect(tempo.workLength == tempoWork && tempo.workCount == 1...1)
    }

    @Test("an RPE of 7 or more is hard work, a hill repeat is")
    func rpeIsHard() throws {
        #expect(try BuiltInWorkoutTemplates.sarcomereRun.analysis(athlete: athlete).workLength == 30...90)
        #expect(try BuiltInWorkoutTemplates.baseHillSprints.analysis(athlete: athlete).workLength == 8...8)
    }

    @Test("the analysis carries sport, tag and archived state")
    func carriesMetadata() throws {
        var template = BuiltInWorkoutTemplates.easyRun
        template.archivedDate = Date(timeIntervalSince1970: 0)
        let analysis = try template.analysis(athlete: athlete)
        #expect(analysis.isArchived && analysis.sport == .running && analysis.sessionType == .easy)
    }

    @Test("every built-in template can be analysed and the interval-like ones are tagged")
    func everyBuiltInAnalyses() throws {
        for template in BuiltInWorkoutTemplates.all {
            _ = try template.analysis(athlete: athlete)
        }
        let untagged = BuiltInWorkoutTemplates.all.filter { $0.sessionType == nil }.map(\.name)
        #expect(Set(untagged) == ["Max heart rate test", "Lactate threshold test (30 min)"])
    }
}

@Suite("SessionProfile")
struct SessionProfileTests {
    @Test("progression steps linearly from the low to the high end of the work length")
    func progression() {
        let profile = SessionProfile(sessionType: .interval, workLength: 180...300)
        #expect(profile.progressedWorkLength(microIndex: 0, of: 5) == 180)
        #expect(profile.progressedWorkLength(microIndex: 1, of: 5) == 210)
        #expect(profile.progressedWorkLength(microIndex: 4, of: 5) == 300)
        #expect(profile.progressedWorkLength(microIndex: 9, of: 5) == 300)
        #expect(profile.progressedWorkLength(microIndex: 0, of: 1) == 240)
        #expect(SessionProfile(sessionType: .easy).progressedWorkLength(microIndex: 0, of: 3) == nil)
    }

    @Test("invalid values are dropped")
    func invalidValues() {
        let profile = SessionProfile(sessionType: .interval, workLength: -5...10, workCount: -1...3, raceTargetFraction: .nan)
        #expect(profile.workLength == nil && profile.workCount == nil && profile.raceTargetFraction == nil)
    }

    @Test("round trips, and decodes with only a session type")
    func codable() throws {
        let profile = SessionProfile(sessionType: .interval, workLength: 180...300, workCount: 3...6, raceTargetFraction: 0.95)
        #expect(try JSONDecoder().decode(SessionProfile.self, from: JSONEncoder().encode(profile)) == profile)
        let bare = try JSONDecoder().decode(SessionProfile.self, from: Data(#"{"sessionType":"long"}"#.utf8))
        #expect(bare == SessionProfile(sessionType: .long))
    }

    @Test("a paradigm keeps its profiles per phase and skips one with an unknown session type")
    func paradigmProfiles() throws {
        let paradigm = TrainingParadigm(name: "Test", sessionProfiles: [.build: [SessionProfile(sessionType: .interval, workLength: 180...300), SessionProfile(sessionType: .long)]])
        let decoded = try JSONDecoder().decode(TrainingParadigm.self, from: JSONEncoder().encode(paradigm))
        #expect(decoded.sessionProfiles == paradigm.sessionProfiles)
        let json = #"{"name":"X","sessionProfiles":{"build":[{"sessionType":"nonsense"},{"sessionType":"easy"}]}}"#
        #expect(try JSONDecoder().decode(TrainingParadigm.self, from: Data(json.utf8)).sessionProfiles == [.build: [SessionProfile(sessionType: .easy)]])
        #expect(try JSONDecoder().decode(TrainingParadigm.self, from: Data(#"{"name":"X"}"#.utf8)).sessionProfiles.isEmpty)
        #expect(TrainingParadigm.builtIn.allSatisfy { $0.sessionProfiles.isEmpty })
    }
}

@Suite("TemplateFitter")
struct TemplateFitterTests {
    let athlete = AthleteProfile.fixture()
    let intervals = SessionProfile(sessionType: .interval, workLength: 180...300)

    private func choice(_ fit: TemplateFit) throws -> TemplateChoice {
        guard case .fit(let choice) = fit else { throw FitterTestError.missing }
        return choice
    }

    private func fit(_ profile: SessionProfile, target: TimeInterval = 3600, templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all, previous: [UUID] = [], workLength: TimeInterval? = nil) -> TemplateFit {
        TemplateFitter.fit(profile: profile, targetSeconds: target, templates: templates, previous: previous, workLength: workLength, athlete: athlete)
    }

    @Test("the filter excludes templates whose work lengths miss the profile, and keeps those that overlap")
    func filter() throws {
        // Short interval run (30-120 s) is out; Long Interval Runs (180-300 s) and Mixed (30-600 s) stay in.
        let both = [BuiltInWorkoutTemplates.shortIntervalRun, BuiltInWorkoutTemplates.longIntervalRun]
        #expect(try choice(fit(intervals, templates: both)).template.id == BuiltInWorkoutTemplates.longIntervalRun.id)
        #expect(fit(intervals, templates: [BuiltInWorkoutTemplates.shortIntervalRun]) == .missingTemplate(intervals))
        let mixed = try choice(fit(intervals, templates: [BuiltInWorkoutTemplates.mixedIntervalRun]))
        #expect(mixed.template.id == BuiltInWorkoutTemplates.mixedIntervalRun.id)
    }

    @Test("the filter requires the session type tag; an untagged, archived or non-running template never matches")
    func tagAndStatus() {
        var untagged = BuiltInWorkoutTemplates.longIntervalRun
        untagged.sessionType = nil
        var archived = BuiltInWorkoutTemplates.longIntervalRun
        archived.archivedDate = Date(timeIntervalSince1970: 0)
        var cycling = BuiltInWorkoutTemplates.longIntervalRun
        cycling.sport = .cycling
        #expect(fit(intervals, templates: [untagged, archived, cycling]) == .missingTemplate(intervals))
        #expect(fit(SessionProfile(sessionType: .interval), templates: []) == .missingTemplate(SessionProfile(sessionType: .interval)))
    }

    @Test("a work count outside what the template can do excludes it")
    func workCountFilter() {
        let profile = SessionProfile(sessionType: .interval, workLength: 180...300, workCount: 10...12)
        #expect(fit(profile, templates: [BuiltInWorkoutTemplates.longIntervalRun]) == .missingTemplate(profile))
    }

    @Test("an athlete's own template takes part when it is tagged")
    func athleteTemplate() throws {
        let custom = WorkoutTemplate(
            name: "My 4 minutes", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "reps", name: "Reps", unit: .count, defaultValue: 4, range: 2...10)],
            blocks: [TemplateBlock(steps: [
                TemplateStep(kind: .work, goal: .time(.fixed(240)), target: .heartRateZone(4)),
                TemplateStep(kind: .recovery, goal: .time(.fixed(120)), target: .heartRateZone(1)),
            ], repetitions: .parameter("reps"))],
            sessionType: .interval
        )
        let picked = try choice(fit(intervals, target: 1800, templates: [custom]))
        #expect(picked.template.id == custom.id)
        // 5 x (240 + 120) = 1800.
        #expect(picked.values["reps"] == 5 && picked.seconds == 1800 && picked.error == 0)
    }

    @Test("closest fit sets the work length and solves the repetitions for the target duration")
    func closestFit() throws {
        let picked = try choice(fit(intervals, target: 3600, templates: [BuiltInWorkoutTemplates.longIntervalRun]))
        #expect(picked.values["work"] == 240)
        // 900 s fixed + reps x (240 + rest 180 default): 6 reps = 3420, 7 reps = 3840; 3420 is 5 % off, 3840 is 6.7 % off.
        #expect(picked.values["reps"] == 6)
        #expect(picked.values["rest"] == 180)
        #expect(picked.seconds == 3420)
        #expect(abs(picked.error - 180.0 / 3600) < 1e-9)
    }

    @Test("an explicit work length is clamped to the template's range")
    func explicitWorkLength() throws {
        let long = try choice(fit(intervals, templates: [BuiltInWorkoutTemplates.longIntervalRun], workLength: 400))
        #expect(long.values["work"] == 300)
        let short = try choice(fit(intervals, templates: [BuiltInWorkoutTemplates.longIntervalRun], workLength: 200))
        #expect(short.values["work"] == 200)
    }

    @Test("a distance-based effort is solved through the pace model")
    func distanceEffort() throws {
        let profile = SessionProfile(sessionType: .interval, workLength: 90...90)
        let picked = try choice(fit(profile, templates: [BuiltInWorkoutTemplates.shortIntervalRunTrack]))
        let meters = picked.values["distance"]!
        #expect(abs(athlete.paceModel.duration(forMeters: meters, atZone: 5) - 90) < 0.01)
    }

    @Test("a long run is sized by its distance parameter to the target duration")
    func longRunVolume() throws {
        let profile = SessionProfile(sessionType: .long)
        let target = 5400.0
        let picked = try choice(fit(profile, target: target, templates: [BuiltInWorkoutTemplates.longRun]))
        #expect(abs(picked.seconds - target) < 1)
        // A target beyond the template's reach takes the end of the range.
        let far = try choice(fit(profile, target: 100_000, templates: [BuiltInWorkoutTemplates.longRun]))
        #expect(far.values["distance"] == 35_000)
    }

    @Test("equal fits break by name, then by id")
    func tie() throws {
        var a = BuiltInWorkoutTemplates.easyRun
        a.name = "A easy"
        var b = BuiltInWorkoutTemplates.easyRun
        b.name = "B easy"
        let picked = try choice(fit(SessionProfile(sessionType: .easy), target: 1800, templates: [b, a]))
        #expect(picked.template.name == "A easy")
        let c = WorkoutTemplate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: a.name, sport: a.sport, parameters: a.parameters, blocks: a.blocks, sessionType: a.sessionType)
        #expect(try choice(fit(SessionProfile(sessionType: .easy), target: 1800, templates: [a, c])).template.id == c.id)
    }

    @Test("rotation moves off the previous template when another fits about as well, not when it fits much worse")
    func rotation() throws {
        let long = BuiltInWorkoutTemplates.longIntervalRun
        let mixed = BuiltInWorkoutTemplates.mixedIntervalRun
        let templates = [long, mixed]
        let first = try choice(fit(intervals, templates: templates))
        let second = try choice(fit(intervals, templates: templates, previous: [first.template.id]))
        #expect(first.template.id != second.template.id)
        #expect(second.error <= first.error + TemplateFitter.rotationTolerance)
        // Alone, the previous template is used again.
        #expect(try choice(fit(intervals, templates: [long], previous: [long.id])).template.id == long.id)
        // A previous template that fits far better stays when the other is more than 10 points worse.
        let tiny = try choice(fit(intervals, target: 900, templates: templates))
        let again = try choice(fit(intervals, target: 900, templates: templates, previous: [tiny.template.id]))
        let others = templates.filter { $0.id != tiny.template.id }
        #expect(others.count == 1)
        if again.template.id != tiny.template.id { #expect(again.error <= tiny.error + TemplateFitter.rotationTolerance) }
    }

    @Test("progression steps the work length across the micros of a phase, for 7, 10 and 14-day micros")
    func progressionAcrossMicros() throws {
        // The volume per session grows with the micro length; the work length depends only on the micro's place.
        for (days, target) in [(7, 2400.0), (10, 3000.0), (14, 3800.0)] {
            var lengths: [Double] = []
            for index in 0..<4 {
                let work = intervals.progressedWorkLength(microIndex: index, of: 4)
                let picked = try choice(fit(intervals, target: target, templates: [BuiltInWorkoutTemplates.longIntervalRun], workLength: work))
                lengths.append(picked.values["work"]!)
                #expect(picked.error < 0.1, "\(days)-day micro \(index)")
            }
            #expect(lengths == [180, 220, 260, 300])
        }
    }

    @Test("the repetitions grow with the micro length at the same work length")
    func repetitionsFollowVolume() throws {
        let reps = try [2700.0, 3600, 5400].map { target in
            try choice(fit(intervals, target: target, templates: [BuiltInWorkoutTemplates.longIntervalRun])).values["reps"]!
        }
        #expect(reps == reps.sorted() && reps.first! < reps.last!)
    }

    @Test("each built-in tag finds a template: easy, recovery, long, tempo, interval, hill repeats")
    func everyTypeHasBuiltIn() throws {
        for type in [SessionType.easy, .recovery, .long, .tempo, .interval, .hillRepeats] {
            _ = try choice(fit(SessionProfile(sessionType: type)))
        }
        #expect(fit(SessionProfile(sessionType: .race)) == .missingTemplate(SessionProfile(sessionType: .race)))
    }
}

private enum FitterTestError: Error { case missing }

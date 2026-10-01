import Foundation
import Testing
@testable import TrainingCore

@Suite("CalendarExport")
struct CalendarExportTests {
    /// 2023-11-14 00:00 UTC, so `day(n)` is midnight UTC n days later.
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
    private let tempoTemplate = WorkoutTemplate(name: "Tempo Run", sport: .running, parameters: [], blocks: [])

    private func workout(name: String = "Tempo 3 × 8 min", templateID: UUID? = nil) -> StructuredWorkout {
        StructuredWorkout(
            name: name, sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(3))])],
            templateID: templateID
        )
    }

    /// A 30-minute run at a steady 150 bpm, starting at `hour` on `day`.
    private func run(on dayOffset: Int, hour: Double = 7, distance: Double = 6000) -> Activity {
        let start = day(dayOffset, hour: hour)
        let samples = (0..<360).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 150) }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 1800, distanceMeters: distance, heartRate: samples)
    }

    private func build(
        activities: [Activity] = [], plans: [PlannedActivity] = [], workouts: [StructuredWorkout] = [],
        metrics: [FitnessMetrics] = [], from first: Int = 0, through last: Int = 6, today: Int = 3
    ) -> CalendarExport {
        CalendarExportBuilder().build(
            from: day(first), through: day(last, hour: 12),
            activities: activities, plans: plans, workouts: workouts, templates: [tempoTemplate],
            metrics: metrics, athlete: athlete, today: day(today, hour: 9), generatedAt: day(today, hour: 9)
        )
    }

    @Test("every day of the period is present, in order, including empty ones")
    func everyDayPresent() {
        let export = build(from: 0, through: 6)

        #expect(export.days.map(\.date) == ["2023-11-14", "2023-11-15", "2023-11-16", "2023-11-17", "2023-11-18", "2023-11-19", "2023-11-20"])
        #expect(export.firstDay == "2023-11-14")
        #expect(export.lastDay == "2023-11-20")
        #expect(export.timeZone == athlete.timeZone.identifier)
        #expect(export.days.allSatisfy { $0.activities.isEmpty && $0.metrics == nil })
    }

    @Test("a completed activity carries its measured TRIMP, sport, start, duration and distance")
    func completedActivity() throws {
        let activity = run(on: 1)

        let entry = try #require(build(activities: [activity]).days[1].activities.first)

        #expect(entry.status == .completed)
        #expect(entry.start == activity.start)
        #expect(entry.sport == "running")
        #expect(entry.name == nil)
        #expect(entry.trimpSource == .heartRate)
        #expect((entry.trimp ?? 0) > 0)
        #expect(entry.durationSeconds == 1800)
        #expect(entry.distanceMeters == 6000)
        #expect(entry.intensity != nil)
        #expect(entry.plan == nil)
    }

    @Test("a fulfilled plan rides along on its activity and gets no entry of its own")
    func fulfilledPlanRidesAlong() throws {
        let tempo = workout(templateID: tempoTemplate.id)
        let activity = run(on: 1)
        let plan = PlannedActivity(workoutID: tempo.id, date: day(1), completedActivityID: activity.id)

        let entries = build(activities: [activity], plans: [plan], workouts: [tempo]).days[1].activities

        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.status == .completed)
        #expect(entry.name == "Tempo 3 × 8 min")
        #expect(entry.template == "Tempo Run")
        let planned = try #require(entry.plan)
        #expect(planned.name == "Tempo 3 × 8 min")
        #expect(planned.trimpSource == .estimated)
        #expect(planned.durationSeconds == 1800)
    }

    @Test("a missed plan is left out; today's and future unfulfilled plans are included")
    func missedPlansLeftOut() {
        let easy = workout(name: "Easy")
        let missed = PlannedActivity(workoutID: easy.id, date: day(2))
        let today = PlannedActivity(workoutID: easy.id, date: day(3))
        let future = PlannedActivity(workoutID: easy.id, date: day(5))

        let export = build(plans: [missed, today, future], workouts: [easy], today: 3)

        #expect(export.days[2].activities.isEmpty)
        #expect(export.days[3].activities.map(\.status) == [.planned])
        #expect(export.days[5].activities.map(\.name) == ["Easy"])
    }

    @Test("a planned workout carries expected TRIMP, duration and its override when set")
    func plannedValues() throws {
        let tempo = workout(templateID: tempoTemplate.id)
        let estimated = PlannedActivity(workoutID: tempo.id, date: day(4))
        let overridden = PlannedActivity(workoutID: tempo.id, date: day(5), expectedLoadOverride: 77)

        let export = build(plans: [estimated, overridden], workouts: [tempo])

        let first = try #require(export.days[4].activities.first)
        #expect(first.status == .planned)
        #expect(first.start == nil)
        #expect(first.template == "Tempo Run")
        #expect(first.trimpSource == .estimated)
        #expect((first.trimp ?? 0) > 0)
        #expect(first.durationSeconds == 1800)
        #expect(first.distanceMeters != nil)
        #expect(first.intensity != nil)
        let second = try #require(export.days[5].activities.first)
        #expect(second.trimp == 77)
        #expect(second.trimpSource == .override)
    }

    @Test("a plan whose workout is missing is left out")
    func planWithoutWorkoutLeftOut() {
        let orphan = PlannedActivity(workoutID: UUID(), date: day(5))

        #expect(build(plans: [orphan]).days[5].activities.isEmpty)
    }

    @Test("metrics are attached per day, with undefined monotony and strain as nil")
    func metricsAttached() throws {
        let flat = FitnessMetrics(
            day: day(2), load: 0, ctl: 40, atl: 30, tsb: 10, monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
        )

        let metrics = try #require(build(metrics: [flat]).days[2].metrics)

        #expect(metrics.ctl == 40)
        #expect(metrics.tsb == 10)
        #expect(metrics.monotony == nil)
        #expect(metrics.strain == nil)
    }

    @Test("days are calendar days in the athlete's time zone: a late-evening run stays on its own day")
    func athleteTimeZoneDays() throws {
        let amsterdam = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190, timeZoneIdentifier: "Europe/Amsterdam")
        // 2023-11-15 23:30 in Amsterdam is 22:30 UTC.
        let lateRun = Activity(source: .healthKit(UUID()), sport: .running, start: Date(timeIntervalSince1970: 1_700_087_400), duration: 1200)

        let export = CalendarExportBuilder().build(
            from: lateRun.start.addingTimeInterval(-86400), through: lateRun.start.addingTimeInterval(86400),
            activities: [lateRun], plans: [], workouts: [], templates: [], metrics: [],
            athlete: amsterdam, today: lateRun.start, generatedAt: lateRun.start
        )

        #expect(export.timeZone == "Europe/Amsterdam")
        #expect(export.days.map(\.date) == ["2023-11-14", "2023-11-15", "2023-11-16"])
        #expect(export.days.map(\.activities.count) == [0, 1, 0])
    }

    @Test("an activity without heart rate is scored from perceived exertion, and says so")
    func perceivedExertionSource() throws {
        let start = day(1, hour: 7)
        let noHeartRate = Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 2400, perceivedExertion: 6)

        let entry = try #require(build(activities: [noHeartRate]).days[1].activities.first)

        #expect(entry.trimpSource == .perceivedExertion)
        #expect((entry.trimp ?? 0) > 0)
    }

    @Test("a manually entered load is labelled manual, not as a plan override")
    func manualLoadLabel() {
        #expect(CalendarExportBuilder.trimpSource(for: .manual) == .manual)
        #expect(CalendarExportBuilder.trimpSource(for: .exponentialTRIMP) == .heartRate)
    }

    @Test("JSON writes null for missing values, so every entry has the same keys, and decodes back")
    func jsonShape() throws {
        let easy = workout(name: "Easy")
        let export = build(
            activities: [run(on: 1)], plans: [PlannedActivity(workoutID: easy.id, date: day(5))], workouts: [easy]
        )

        let data = try export.jsonData()
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"plan\" : null"))
        #expect(json.contains("\"start\" : null"))
        #expect(json.contains("\"metrics\" : null"))
        #expect(json.contains("\"date\" : \"2023-11-15\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(CalendarExport.self, from: data).days.count == export.days.count)
    }
}

@MainActor
@Suite("TrainingModel.calendarExport", .serialized)
struct TrainingModelCalendarExportTests {
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private func run(on dayOffset: Int) -> Activity {
        let start = day(dayOffset, hour: 7)
        let samples = (0..<360).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 150) }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 1800, heartRate: samples)
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)))
    }

    @Test("the export reads the store and leaves the model's loaded state alone")
    func leavesModelAlone() async throws {
        let (store, model) = makeModel()
        try await store.upsert([run(on: 2)])

        let export = try await model.calendarExport(from: day(0), through: day(6), asOf: day(6))

        #expect(model.activities.isEmpty)
        #expect(model.metrics.isEmpty)
        #expect(export.days[2].activities.count == 1)
    }

    @Test("CTL is warmed up from history before the period, matching a full-history series")
    func warmedUpMetrics() async throws {
        let (store, model) = makeModel()
        // Three months of runs every other day before the period, and one inside it.
        try await store.upsert(stride(from: -90, to: 0, by: 2).map(run(on:)) + [run(on: 2)])

        let export = try await model.calendarExport(from: day(0), through: day(6), asOf: day(6))
        try await model.load(in: day(-120)...day(6), asOf: day(6))

        let exported = try #require(export.days[3].metrics)
        let full = try #require(model.metrics.first { CalendarExportBuilder.dayString($0.day, calendar: Self.utc) == "2023-11-17" })
        #expect(exported.ctl > 10)
        #expect(abs(exported.ctl - full.ctl) < 0.01)
        #expect(abs(exported.atl - full.atl) < 0.01)
    }

    @Test("a future period (the season plan) carries fitness forward from past training, then projects it")
    func futurePeriodWarmsUpFromPast() async throws {
        let (store, model) = makeModel()
        try await store.upsert(stride(from: -60, to: 0, by: 2).map(run(on:)))

        let export = try await model.calendarExport(from: day(10), through: day(20), asOf: day(0, hour: 12))

        let ctl = export.days.compactMap { $0.metrics?.ctl }
        #expect(ctl.count == 11)
        #expect((ctl.first ?? 0) > 5)
        #expect(zip(ctl, ctl.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(export.days.allSatisfy { $0.metrics?.isProjected == true })
        #expect(export.days.allSatisfy { $0.activities.isEmpty })
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

import Foundation
import Testing
@testable import TrainingCore

/// A provider whose plan is a row of micros with a metrics series made by closures of the levers.
private final class StubProvider: PlanCandidateProvider, @unchecked Sendable {
    static let start = Date(timeIntervalSince1970: 1_799_971_200) // a UTC midnight

    let microLength: Int
    let microCount: Int
    let tsb: @Sendable (Int, PlanLevers) -> Double
    let monotony: @Sendable (Int, PlanLevers) -> Double
    let sessions: @Sendable (PlanLevers) -> [PlanSession]
    let compromises: [PlanCompromise]
    let failing: Bool
    private let lock = NSLock()
    private var _calls: [PlanLevers] = []
    var calls: [PlanLevers] { lock.withLock { _calls } }

    init(
        microLength: Int = 7,
        microCount: Int = 4,
        tsb: @escaping @Sendable (Int, PlanLevers) -> Double = { _, _ in 0 },
        monotony: @escaping @Sendable (Int, PlanLevers) -> Double = { _, _ in .nan },
        sessions: @escaping @Sendable (PlanLevers) -> [PlanSession] = { _ in [] },
        compromises: [PlanCompromise] = [],
        failing: Bool = false
    ) {
        self.microLength = microLength
        self.microCount = microCount
        self.tsb = tsb
        self.monotony = monotony
        self.sessions = sessions
        self.compromises = compromises
        self.failing = failing
    }

    static func day(_ index: Int) -> Date { start.addingTimeInterval(Double(index) * 86400) }

    func candidate(levers: PlanLevers, today: Date) async throws -> PlanCandidate {
        lock.withLock { _calls.append(levers) }
        if failing { throw StubError.failed }
        let days = microLength * microCount
        let macro = TrainingCycle(level: .macro, phase: .build, name: "Macro", dateRange: Self.day(0)...Self.day(days - 1))
        let micros = (0..<microCount).map { index in
            TrainingCycle(
                level: .micro, phase: .build, loadRole: .build, name: "Micro \(index)",
                dateRange: Self.day(index * microLength)...Self.day((index + 1) * microLength - 1), parentID: macro.id
            )
        }
        let metrics = (0..<days).map { index in
            FitnessMetrics(
                day: Self.day(index), load: 50, ctl: 50, atl: 50, tsb: tsb(index, levers),
                monotony: monotony(index, levers), strain: .nan, isProjected: true, isWarmingUp: false
            )
        }
        return PlanCandidate(cycles: [macro] + micros, plannedActivities: [], sessions: sessions(levers), metrics: metrics, compromises: compromises)
    }
}

private enum StubError: Error { case failed }

@Suite("PlanAdjuster")
struct PlanAdjusterTests {
    private let today = StubProvider.day(-1)
    private func day(_ index: Int) -> Date { StubProvider.day(index) }

    @Test("An acceptable first plan is returned unchanged, built once")
    func acceptableUnchanged() async throws {
        let provider = StubProvider()
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.outcome == .acceptable)
        #expect(proposal.history.isEmpty)
        #expect(proposal.levers == .none)
        #expect(proposal.compromises.isEmpty)
        #expect(provider.calls == [.none])
    }

    @Test("Lowering volume answers a low TSB, in as many steps as it takes", arguments: [7, 10, 14])
    func lowerVolumeFixesTSBBand(microLength: Int) async throws {
        // Risk on the first day of micro 1 until that micro is at 0.75 or less: 0.9 and 0.81 each move TSB closer, 0.729 clears it.
        let provider = StubProvider(microLength: microLength, tsb: { index, levers in
            guard index == microLength else { return 0 }
            return -40 + 50 * (1 - levers.volumeScale(forMicro: StubProvider.day(microLength)))
        })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.outcome == .acceptable)
        #expect(proposal.history.count == 3)
        #expect(proposal.history.allSatisfy { $0.kept && $0.answering == .tsbBand })
        guard case .lowerVolume(let start, let scale) = proposal.history.last?.adjustment else {
            Issue.record("expected a volume step"); return
        }
        #expect(start == day(microLength))
        #expect(abs(scale - 0.729) < 1e-9)
        #expect(proposal.compromises.count == 3)
    }

    @Test("A down-week answers a low TSB the volume cannot fix; the failed step is not kept")
    func downWeekFixesTSBBand() async throws {
        let provider = StubProvider(tsb: { index, levers in
            index == 7 && !levers.downWeeks.contains(StubProvider.day(7)) ? -40 : 0
        })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.history.map(\.kept) == [false, true])
        #expect(proposal.history.last?.adjustment == .downWeek(microStart: day(7)))
        #expect(proposal.levers == PlanLevers(downWeeks: [day(7)]))
        #expect(proposal.compromises == [.adjusted(.downWeek(microStart: day(7)), answering: .tsbBand)])
    }

    @Test("Easing the session answers a high monotony")
    func easeFixesMonotony() async throws {
        let provider = StubProvider(monotony: { index, levers in
            index == 9 && !levers.easedDays.contains(StubProvider.day(9)) ? 3 : .nan
        })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.history.map(\.adjustment) == [.easeSession(day: day(9))])
    }

    @Test("Dropping the session answers a high monotony easing cannot fix")
    func dropFixesMonotony() async throws {
        let provider = StubProvider(monotony: { index, levers in
            index == 9 && !levers.droppedDays.contains(StubProvider.day(9)) ? 3 : .nan
        })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.history.map(\.adjustment) == [.easeSession(day: day(9)), .dropSession(day: day(9))])
        #expect(proposal.history.map(\.kept) == [false, true])
    }

    @Test("Dropping a run answers a jump over the longest run of the last 28 days")
    func dropFixesLongestRun() async throws {
        let provider = StubProvider(sessions: { levers in
            let runs = [(10, 3600.0), (20, 7200.0)]
            return runs.filter { !levers.droppedDays.contains(StubProvider.day($0.0)) }
                .map { PlanSession(day: StubProvider.day($0.0), seconds: $0.1, intensity: .low, speed: .slow) }
        })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.history.last?.adjustment == .dropSession(day: day(20)))
        #expect(proposal.history.last?.answering == .longestRun)
    }

    @Test("The loop stops at the bound and reports the risks left")
    func boundRespected() async throws {
        let provider = StubProvider(tsb: { index, levers in
            index == 8 ? -40 + 2 * (1 - levers.volumeScale(forMicro: StubProvider.day(7))) : 0
        })
        let proposal = try await PlanAdjuster(maxIterations: 3).propose(using: provider, today: today)
        #expect(!proposal.isAcceptable)
        #expect(proposal.outcome == .iterationLimit)
        #expect(proposal.history.count == 3)
        #expect(provider.calls.count == 4)
        #expect(proposal.risks.map(\.rule) == [.tsbBand])
        #expect(proposal.risks.first?.day == day(8))
    }

    @Test("With nothing left to try the loop stops, never repeating a set of levers")
    func noAdjustmentLeftAndNoRepeat() async throws {
        let provider = StubProvider(tsb: { index, levers in
            index == 8 ? -40 + 2 * (1 - levers.volumeScale(forMicro: StubProvider.day(7))) : 0
        })
        let proposal = try await PlanAdjuster(maxIterations: 100).propose(using: provider, today: today)
        #expect(!proposal.isAcceptable)
        #expect(proposal.outcome == .noAdjustmentLeft)
        #expect(Set(provider.calls).count == provider.calls.count)
        #expect(Set(proposal.history.map(\.adjustment)).count == proposal.history.count)
        // Volume steps down to the floor (seven kept steps), then the down-week, which does not help.
        #expect(proposal.history.last?.adjustment == .downWeek(microStart: day(7)))
        #expect(proposal.levers.volumeScale(forMicro: day(7)) == 0.5)
    }

    @Test("An adjustment that makes things worse is not kept")
    func worseNotKept() async throws {
        // Lowering volume in micro 1 fixes its TSB risk but creates two others elsewhere.
        let provider = StubProvider(tsb: { index, levers in
            if index == 8 && levers.volumeScales.isEmpty { return -40 }
            if (index == 20 || index == 21) && !levers.volumeScales.isEmpty { return -40 }
            return 0
        })
        let proposal = try await PlanAdjuster(maxIterations: 1).propose(using: provider, today: today)
        #expect(proposal.history.map(\.kept) == [false])
        #expect(proposal.levers == .none)
        #expect(proposal.risks.count == 1)
    }

    @Test("Warnings are surfaced and do not block the proposal")
    func warningsSurfaced() async throws {
        let race = Race(name: "Race", date: day(27), priority: .primary, distanceMeters: 42_195)
        let provider = StubProvider(tsb: { index, _ in
            switch index {
            case 27: 40 // past maxTSBOnRaceDay
            case 3: 30 // past maxAcceptableTSB
            default: 0
            }
        })
        let proposal = try await PlanAdjuster(races: [race], targetRace: race).propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.outcome == .acceptable)
        #expect(proposal.history.isEmpty)
        #expect(proposal.risks.isEmpty)
        // Day 27 is past the race-day and the any-day ceiling, day 3 past the any-day ceiling.
        #expect(proposal.warnings.map(\.rule).sorted { "\($0)" < "\($1)" } == [.raceDayTSB, .tsbBand, .tsbBand])
        #expect(proposal.evaluation.findings.count == 3)
        #expect(proposal.targetRaceID == race.id)
    }

    @Test("The loop answers the risk and leaves the warnings alone")
    func warningsKeptWhileFixingRisk() async throws {
        let race = Race(name: "Race", date: day(27), priority: .primary, distanceMeters: 42_195)
        let provider = StubProvider(tsb: { index, levers in
            if index == 27 { return 40 }
            return index == 8 && levers.volumeScales.isEmpty ? -40 : 0
        })
        let proposal = try await PlanAdjuster(races: [race]).propose(using: provider, today: today)
        #expect(proposal.isAcceptable)
        #expect(proposal.history.count == 1)
        #expect(proposal.warnings.contains { $0.rule == .raceDayTSB })
        #expect(proposal.warnings.allSatisfy { $0.day == day(27) })
    }

    @Test("The provider's compromises come first, then the adjustments kept")
    func compromisesListed() async throws {
        let lead = PlanCompromise.leadTime(LeadTimeCompromise(action: .phaseDropped(.conditioning), reason: .leadTimeTooShort(availableMicros: 4, neededMicros: 6)))
        let missing = PlanCompromise.missingTemplate(microStart: day(0), SessionProfile(sessionType: .interval))
        let provider = StubProvider(
            tsb: { index, levers in index == 8 && levers.volumeScales.isEmpty ? -40 : 0 },
            compromises: [lead, missing, .overriddenPreference(.maxWeeklyVolume)]
        )
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        #expect(proposal.compromises == [
            lead, missing, .overriddenPreference(.maxWeeklyVolume),
            .adjusted(.lowerVolume(microStart: day(7), scale: 0.9), answering: .tsbBand),
        ])
    }

    @Test("A draft plan is created on the injected day and joins the cycles and workouts")
    func draftPlan() async throws {
        let proposal = try await PlanAdjuster().propose(using: StubProvider(), today: today)
        let plan = proposal.draftPlan(named: "Marathon")
        #expect(plan.status == .draft)
        #expect(plan.createdDate == today)
        #expect(plan.macroCycleID == proposal.candidate.cycles.first { $0.level == .macro }?.id)
        let stamped = proposal.stamped(with: plan)
        #expect(stamped.cycles.allSatisfy { $0.planID == plan.id })
        #expect(stamped.cycles.count == proposal.candidate.cycles.count)
    }

    @Test("A provider error propagates")
    func providerError() async {
        await #expect(throws: StubError.self) {
            try await PlanAdjuster().propose(using: StubProvider(failing: true), today: today)
        }
    }

    @Test("A proposal survives an encode and decode")
    func codableRoundTrip() async throws {
        let provider = StubProvider(tsb: { index, levers in index == 8 && levers.volumeScales.isEmpty ? -40 : 0 })
        let proposal = try await PlanAdjuster().propose(using: provider, today: today)
        // The stub's metrics carry NaN monotony, which JSON only holds as a string.
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let decoded = try decoder.decode(PlanProposal.self, from: try encoder.encode(proposal))
        #expect(decoded.history == proposal.history)
        #expect(decoded.levers == proposal.levers)
        #expect(decoded.compromises == proposal.compromises)
        #expect(decoded.evaluation == proposal.evaluation)
    }
}

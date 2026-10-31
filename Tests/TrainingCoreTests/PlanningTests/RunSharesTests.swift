import Foundation
import Testing
@testable import TrainingCore

@Suite("Run shares of a micro (MVP5-158)")
struct RunSharesTests {
    private func run(_ day: Int, _ type: RunType) -> DayAssignment {
        DayAssignment(day: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86400), slot: .morning, runType: type)
    }

    @Test("a long run takes 30 %, a hard run an equal part of the rest, the easy runs alternate 20 % above and below their average")
    func fourRuns() {
        let runs = [run(0, .interval), run(1, .easy), run(2, .easy), run(3, .long)]
        let shares = PlanGenerator.shares(of: runs, seconds: 18_000)

        #expect(shares[runs[3]] == 5_400)
        // The remaining 12,600 s: weights 1 (hard), 1.2 and 0.8 (easy, averaging 1).
        #expect(abs((shares[runs[0]] ?? 0) - 4_200) < 1e-6)
        #expect(abs((shares[runs[1]] ?? 0) - 5_040) < 1e-6)
        #expect(abs((shares[runs[2]] ?? 0) - 3_360) < 1e-6)
        #expect(abs(shares.values.reduce(0, +) - 18_000) < 1e-6)
    }

    @Test("the shares add up to the volume for any mix of runs, and the easy runs are not all equal")
    func addUp() {
        let types: [[RunType]] = [[.easy], [.long], [.easy, .easy, .easy], [.easy, .long], [.interval, .threshold, .easy, .recovery, .long],
                                  [.long, .long, .easy], [.easy, .easy, .easy, .easy, .easy, .easy, .easy]]
        for mix in types {
            let runs = mix.enumerated().map { run($0.offset, $0.element) }
            let shares = PlanGenerator.shares(of: runs, seconds: 21_600)
            #expect(abs(shares.values.reduce(0, +) - 21_600) < 1e-6, "\(mix)")
            #expect(shares.count == runs.count, "\(mix)")
            if mix.filter({ $0 == .easy }).count >= 2 {
                #expect(Set(runs.filter { $0.runType == .easy }.compactMap { shares[$0] }.map { Int($0) }).count > 1, "\(mix)")
            }
        }
    }

    @Test("a micro with only long runs, or no runs, is handled")
    func degenerate() {
        #expect(PlanGenerator.shares(of: [], seconds: 3_600).isEmpty)
        let only = [run(0, .long)]
        #expect(PlanGenerator.shares(of: only, seconds: 3_600)[only[0]] == 3_600)
    }
}

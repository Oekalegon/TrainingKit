import Foundation
import Testing
@testable import TrainingCore

@Suite("CyclePhase and MicroLoadRole coding")
struct CyclePhaseCodingTests {
    /// A `TrainingCycle` payload as written before phases became named values: the phase (and level)
    /// were synthesised enum cases (`{"build":{}}`) and there was no `loadRole`.
    static func legacyCyclePayload(level: String, phase: String) -> Data {
        Data("""
        {"id":"\(UUID().uuidString)","level":{"\(level)":{}},"phase":{"\(phase)":{}},"name":"Week 1",
         "dateRange":[1000,2000]}
        """.utf8)
    }

    @Test("a phase encodes as its plain id string and round-trips, including paradigm-defined names")
    func phaseRoundTrip() throws {
        let data = try JSONEncoder().encode(["a": CyclePhase("structural")])
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":"structural"}"#)
        #expect(try JSONDecoder().decode([String: CyclePhase].self, from: data)["a"] == "structural")
    }

    @Test("every legacy enum phase decodes to the matching constant")
    func legacyPhases() throws {
        let legacy: [(String, CyclePhase)] = [
            ("base", .base), ("build", .build), ("peak", .peak), ("taper", .taper),
            ("race", .race), ("recovery", .recovery), ("transition", .transition),
        ]
        for (name, expected) in legacy {
            let decoded = try JSONDecoder().decode([CyclePhase].self, from: Data(#"[{"\#(name)":{}}]"#.utf8))
            #expect(decoded == [expected], "\(name)")
        }
    }

    @Test("a phase that is neither a string nor a one-case object fails to decode")
    func malformedPhase() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CyclePhase.self, from: Data("{}".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CyclePhase.self, from: Data(#"{"a":{},"b":{}}"#.utf8)) }
    }

    @Test("a legacy micro derives its load role from its stored phase")
    func legacyMicroRole() throws {
        let expected: [(String, MicroLoadRole)] = [
            ("build", .build), ("recovery", .recovery), ("taper", .taper), ("race", .race), ("base", .build), ("peak", .build),
        ]
        for (phase, role) in expected {
            let cycle = try JSONDecoder().decode(TrainingCycle.self, from: Self.legacyCyclePayload(level: "micro", phase: phase))
            #expect(cycle.phase == CyclePhase(phase) && cycle.loadRole == role, "\(phase)")
        }
    }

    @Test("a legacy macro or meso cycle gets no load role")
    func legacyMesoRole() throws {
        let cycle = try JSONDecoder().decode(TrainingCycle.self, from: Self.legacyCyclePayload(level: "meso", phase: "build"))
        #expect(cycle.loadRole == nil)
    }

    @Test("a cycle with a stored load role keeps it and round-trips")
    func roleRoundTrip() throws {
        let cycle = TrainingCycle(level: .micro, phase: "structural", loadRole: .recovery, name: "Week 2", dateRange: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 86_400))
        let decoded = try JSONDecoder().decode(TrainingCycle.self, from: JSONEncoder().encode(cycle))
        #expect(decoded == cycle)
    }

    @Test("a micro created without a role derives it from its phase; a meso drops any role")
    func initDerivesRole() {
        let range = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 86_400)
        #expect(TrainingCycle(level: .micro, phase: .recovery, name: "w", dateRange: range).loadRole == .recovery)
        #expect(TrainingCycle(level: .micro, phase: "structural", name: "w", dateRange: range).loadRole == .build)
        #expect(TrainingCycle(level: .meso, phase: .build, loadRole: .build, name: "m", dateRange: range).loadRole == nil)
    }

    @Test("a mesocycle template stored with microPhases decodes to load roles")
    func legacyTemplate() throws {
        let legacy = Data(#"{"name":"3:1","microPhases":[{"build":{}},{"build":{}},{"recovery":{}}],"microLengthDays":10,"recoveryLoadFraction":0.6,"buildLoadStep":0.08}"#.utf8)
        let template = try JSONDecoder().decode(MesocycleTemplate.self, from: legacy)
        #expect(template.microRoles == [.build, .build, .recovery])
        #expect(template.microLengthDays == 10)
        #expect(try JSONDecoder().decode(MesocycleTemplate.self, from: JSONEncoder().encode(template)) == template)
    }

    @Test("InMemoryStore holds a cycle decoded from a legacy payload")
    func inMemoryStoreLegacy() async throws {
        let cycle = try JSONDecoder().decode(TrainingCycle.self, from: Self.legacyCyclePayload(level: "micro", phase: "recovery"))
        let store = InMemoryStore()
        try await store.upsert([cycle])
        let fetched = try await store.cycle(id: cycle.id)
        #expect(fetched?.phase == .recovery && fetched?.loadRole == .recovery)
    }
}

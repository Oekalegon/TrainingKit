import Foundation
import Testing
import TrainingCore
@testable import TrainingTools

@Suite("ToolRegistry")
struct ToolRegistryTests {
    struct EchoTool: TrainingTool {
        struct Input: ToolInput {
            var message: String
            static let example = Input(message: "hello")
        }
        struct Output: Codable, Sendable, Equatable {
            var echoed: String
        }

        static let name = "echo"
        static let description = "Echoes the input message back"
        static let isMutating = false

        func run(_ input: Input, context: ToolContext) async throws -> Output {
            Output(echoed: input.message)
        }
    }

    private func makeContext() async throws -> ToolContext {
        let store = InMemoryStore()
        let athlete = AthleteProfile.fixture()
        try await store.save(athlete)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let sandbox = try await PlanSandbox(snapshotOf: stores)
        return ToolContext(stores: stores, sandbox: sandbox, today: Date(), athlete: athlete)
    }

    @Test("schemas() reports every registered tool")
    func schemasIncludeRegisteredTools() {
        var registry = ToolRegistry()
        registry.register(EchoTool())
        let schemas = registry.schemas()
        #expect(schemas.map(\.name) == ["echo"])
        #expect(schemas[0].isMutating == false)
    }

    @Test("dispatch decodes arguments, runs the tool, and encodes the output")
    func dispatchRunsTheNamedTool() async throws {
        var registry = ToolRegistry()
        registry.register(EchoTool())
        let context = try await makeContext()

        let arguments = try JSONEncoder().encode(EchoTool.Input(message: "hi there"))
        let resultData = try await registry.dispatch(name: "echo", argumentsJSON: arguments, context: context)
        let output = try JSONDecoder().decode(EchoTool.Output.self, from: resultData)

        #expect(output.echoed == "hi there")
    }

    @Test("dispatch throws for an unregistered tool name")
    func dispatchThrowsForUnknownTool() async throws {
        let registry = ToolRegistry()
        let context = try await makeContext()

        await #expect(throws: ToolRegistryError.unknownTool("nope")) {
            _ = try await registry.dispatch(name: "nope", argumentsJSON: Data(), context: context)
        }
    }

    @Test("dispatch wraps malformed arguments as ToolDispatchError.invalidArguments, distinct from a tool's own failures")
    func dispatchWrapsMalformedArguments() async throws {
        var registry = ToolRegistry()
        registry.register(EchoTool())
        let context = try await makeContext()

        let malformedArguments = Data(#"{"wrongField": 1}"#.utf8)

        do {
            _ = try await registry.dispatch(name: "echo", argumentsJSON: malformedArguments, context: context)
            Issue.record("expected dispatch to throw")
        } catch let ToolDispatchError.invalidArguments(tool, _) {
            #expect(tool == "echo")
        } catch {
            Issue.record("expected ToolDispatchError.invalidArguments, got \(error)")
        }
    }

    @Test("dispatch decodes fractional-second ISO 8601 timestamps, which JSONDecoder's built-in .iso8601 strategy rejects")
    func dispatchDecodesFractionalSecondTimestamps() async throws {
        struct DatedTool: TrainingTool {
            struct Input: ToolInput {
                var start: Date
                static let example = Input(start: Date(timeIntervalSince1970: 0))
            }
            struct Output: Codable, Sendable, Equatable {
                var receivedStart: Date
            }
            static let name = "dated"
            static let description = "Echoes back the decoded start date"
            static let isMutating = false
            func run(_ input: Input, context: ToolContext) async throws -> Output {
                Output(receivedStart: input.start)
            }
        }

        var registry = ToolRegistry()
        registry.register(DatedTool())
        let context = try await makeContext()

        let arguments = Data(#"{"start": "2026-01-01T00:00:00.000Z"}"#.utf8)
        let resultData = try await registry.dispatch(name: "dated", argumentsJSON: arguments, context: context)
        let output = try ToolRegistry.defaultDecoder.decode(DatedTool.Output.self, from: resultData)

        #expect(output.receivedStart == Date(timeIntervalSince1970: 1_767_225_600))
    }
}

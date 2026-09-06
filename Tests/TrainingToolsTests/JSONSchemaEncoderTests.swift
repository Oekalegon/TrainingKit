import Foundation
import Testing
@testable import TrainingTools

@Suite("JSONSchemaEncoder")
struct JSONSchemaEncoderTests {
    enum Sport: String, ToolEnumSchema, Codable {
        case running, cycling
    }

    struct SampleInput: ToolInput {
        @ToolDescription("The range's start day")
        var start: Date = Date(timeIntervalSince1970: 0)
        var sport: Sport
        var tags: [String]
        var note: String?

        static let example = SampleInput(start: Date(timeIntervalSince1970: 0), sport: .running, tags: ["easy"], note: "hi")
    }

    @Test("reflects a struct into an object schema with per-field types")
    func objectSchema() {
        let schema = JSONSchemaEncoder.schema(for: SampleInput.self)
        guard case let .object(properties, required, _) = schema else {
            Issue.record("expected an object schema")
            return
        }

        #expect(Set(required) == ["start", "sport", "tags"])
        #expect(properties["note"] == .string(description: nil))

        guard case let .string(description) = properties["start"] else {
            Issue.record("expected start to be a string schema")
            return
        }
        #expect(description == "The range's start day")

        #expect(properties["sport"] == .enumeration(values: ["running", "cycling"], description: nil))

        guard case let .array(items, _) = properties["tags"] else {
            Issue.record("expected tags to be an array schema")
            return
        }
        #expect(items == .string(description: nil))
    }

    @Test("input with no fields schemas as an empty object")
    func noInputSchema() {
        let schema = JSONSchemaEncoder.schema(for: NoToolInput.self)
        #expect(schema == .object(properties: [:], required: [], description: nil))
    }

    struct WithNilOptionals: ToolInput {
        var count: Int?
        var tags: [String]?
        static let example = WithNilOptionals(count: nil, tags: nil)
    }

    @Test("a nil Optional<Int> example still infers the scalar type")
    func nilScalarOptionalInfersType() {
        let schema = JSONSchemaEncoder.schema(for: WithNilOptionals.self)
        guard case let .object(properties, required, _) = schema else {
            Issue.record("expected an object schema")
            return
        }
        #expect(properties["count"] == .integer(description: nil))
        #expect(required.isEmpty)
    }

    @Test("a nil Optional<[String]> example falls back to an empty object, not a wrong-typed string")
    func nilCollectionOptionalFallsBackToObject() {
        let schema = JSONSchemaEncoder.schema(for: WithNilOptionals.self)
        guard case let .object(properties, _, _) = schema else {
            Issue.record("expected an object schema")
            return
        }
        #expect(properties["tags"] == .object(properties: [:], required: [], description: nil))
    }

    struct DayRange: Codable, Sendable, Equatable {
        var start: Date
        var end: Date
    }

    struct WithNestedStructAndSet: ToolInput {
        var range: DayRange
        var sports: Set<String>
        static let example = WithNestedStructAndSet(
            range: DayRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1)),
            sports: ["running"]
        )
    }

    @Test("a nested Codable struct field recurses into an object schema")
    func nestedStructFieldRecurses() {
        let schema = JSONSchemaEncoder.schema(for: WithNestedStructAndSet.self)
        guard case let .object(properties, required, _) = schema else {
            Issue.record("expected an object schema")
            return
        }
        #expect(Set(required) == ["range", "sports"])
        guard case let .object(rangeProperties, rangeRequired, _) = properties["range"] else {
            Issue.record("expected range to be a nested object schema")
            return
        }
        #expect(Set(rangeRequired) == ["start", "end"])
        #expect(rangeProperties["start"] == .string(description: nil))
    }

    @Test("a Set field schemas as an array of its element type")
    func setFieldSchemasAsArray() {
        let schema = JSONSchemaEncoder.schema(for: WithNestedStructAndSet.self)
        guard case let .object(properties, _, _) = schema else {
            Issue.record("expected an object schema")
            return
        }
        guard case let .array(items, _) = properties["sports"] else {
            Issue.record("expected sports to be an array schema")
            return
        }
        #expect(items == .string(description: nil))
    }

    @Test("ToolSchema encodes to the expected JSON Schema shape")
    func toolSchemaEncoding() throws {
        let schema = ToolSchema(
            name: "list_things",
            description: "Lists things",
            isMutating: false,
            inputSchema: .object(properties: ["id": .string(description: "an id")], required: ["id"], description: nil)
        )
        let data = try JSONEncoder().encode(schema.inputSchema)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "object")
        #expect(json?["required"] as? [String] == ["id"])
    }
}

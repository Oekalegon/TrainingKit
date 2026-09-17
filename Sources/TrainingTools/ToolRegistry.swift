import Foundation

/// The set of ``TrainingTool``s available to a model, keyed by name.
///
/// One source of truth: adapters (`TrainingToolsAnthropic`, `TrainingToolsFoundationModels`)
/// both render ``schemas()`` into their provider's tool format and both dispatch through
/// ``dispatch(name:argumentsJSON:context:)``, so neither needs to know a tool's concrete type.
public struct ToolRegistry: Sendable {
    private struct RegisteredTool: Sendable {
        let schema: ToolSchema
        let dispatch: @Sendable (Data, ToolContext) async throws -> Data
    }

    private var toolsByName: [String: RegisteredTool] = [:]
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Creates an empty registry. Register tools with ``register(_:)``.
    ///
    /// - Parameters:
    ///   - decoder: Decodes each tool's `Input` from `dispatch`'s `argumentsJSON`.
    ///   - encoder: Encodes each tool's `Output` for `dispatch`'s return value.
    public init(decoder: JSONDecoder = ToolRegistry.defaultDecoder, encoder: JSONEncoder = ToolRegistry.defaultEncoder) {
        self.decoder = decoder
        self.encoder = encoder
    }

    /// Adds `tool` to the registry, overwriting any existing tool of the same `Tool.name`.
    public mutating func register<Tool: TrainingTool>(_ tool: Tool) {
        let schema = ToolSchema(
            name: Tool.name,
            description: Tool.description,
            isMutating: Tool.isMutating,
            inputSchema: JSONSchemaEncoder.schema(for: Tool.Input.self)
        )
        let decoder = self.decoder
        let encoder = self.encoder
        toolsByName[Tool.name] = RegisteredTool(schema: schema) { argumentsJSON, context in
            let input: Tool.Input
            do {
                input = try decoder.decode(Tool.Input.self, from: argumentsJSON)
            } catch {
                throw ToolDispatchError.invalidArguments(tool: Tool.name, underlying: error)
            }

            let output = try await tool.run(input, context: context)

            do {
                return try encoder.encode(output)
            } catch {
                throw ToolDispatchError.invalidOutput(tool: Tool.name, underlying: error)
            }
        }
    }

    /// Every registered tool's schema, sorted by name for a stable tools-array rendering.
    public func schemas() -> [ToolSchema] {
        toolsByName.values.map(\.schema).sorted { $0.name < $1.name }
    }

    /// Decodes `argumentsJSON` as the named tool's `Input`, runs it, and encodes its `Output`.
    ///
    /// - Throws: ``ToolRegistryError/unknownTool(_:)`` if no tool is registered as `name`;
    ///   ``ToolDispatchError/invalidArguments(tool:underlying:)`` if `argumentsJSON` doesn't
    ///   decode as the tool's `Input` — an adapter's tool-use loop can catch this specifically to
    ///   feed the failure back to the model as a correctable error rather than aborting the loop;
    ///   ``ToolDispatchError/invalidOutput(tool:underlying:)`` if the tool's `Output` fails to
    ///   encode (a bug in the tool, not a model-correctable error); otherwise whatever the tool's
    ///   `run` itself throws.
    public func dispatch(name: String, argumentsJSON: Data, context: ToolContext) async throws -> Data {
        guard let tool = toolsByName[name] else {
            throw ToolRegistryError.unknownTool(name)
        }
        return try await tool.dispatch(argumentsJSON, context)
    }

    /// Decodes dates as ISO 8601, accepting both fractional-second (`...00.000Z`, the form an
    /// LLM is likely to emit) and whole-second timestamps — `JSONDecoder`'s built-in `.iso8601`
    /// strategy only accepts the latter and throws on the former.
    public static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // A fresh formatter per call, rather than a shared captured instance: tool dispatch
            // is not a hot path, and `ISO8601DateFormatter` isn't documented as thread-safe to
            // share across concurrent decodes, which a captured instance in this `@Sendable`
            // closure would be.
            let withFractionalSeconds = ISO8601DateFormatter()
            withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractionalSeconds.date(from: string) {
                return date
            }

            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO 8601 date string, got \(string)"
            )
        }
        return decoder
    }()

    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

public enum ToolRegistryError: Error, Sendable, Equatable {
    case unknownTool(String)
}

/// A failure from ``ToolRegistry/dispatch(name:argumentsJSON:context:)`` that isn't the tool's
/// own `run` throwing.
public enum ToolDispatchError: Error, Sendable {
    /// `argumentsJSON` didn't decode as the named tool's `Input` — typically a model-generated
    /// mistake an adapter's tool-use loop can feed back as a correctable `tool_result` error.
    case invalidArguments(tool: String, underlying: any Error)
    /// The named tool's `Output` failed to encode — a bug in the tool, not a model mistake.
    case invalidOutput(tool: String, underlying: any Error)
}

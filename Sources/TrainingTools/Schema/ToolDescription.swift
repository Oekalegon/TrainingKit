import Foundation

/// Attaches a per-field description to a ``TrainingTool`` `Input` property, surfaced in the
/// generated ``JSONSchema`` so the model knows what the field means.
///
/// ```swift
/// struct Input: ToolInput {
///     @ToolDescription("ISO 8601 start of the range to list activities for")
///     var start: Date = .distantPast
/// }
/// ```
///
/// The property needs an assigned default value — that's what tells Swift to elaborate
/// `@ToolDescription("...") var start: Date = .distantPast` as
/// `ToolDescription(wrappedValue: .distantPast, "...")` rather than treating the parenthesized
/// description as the wrapper's entire (mismatched) initializer argument list.
///
/// Encodes/decodes transparently as the wrapped value — the description only exists for
/// ``JSONSchemaEncoder`` to read off ``ToolInput/example``, via ``ToolDescriptionProviding``.
@propertyWrapper
public struct ToolDescription<Value: Codable & Sendable>: Sendable {
    public var wrappedValue: Value
    public let fieldDescription: String

    public init(wrappedValue: Value, _ fieldDescription: String) {
        self.wrappedValue = wrappedValue
        self.fieldDescription = fieldDescription
    }
}

extension ToolDescription: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
        fieldDescription = ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension ToolDescription: Equatable where Value: Equatable {}
extension ToolDescription: Hashable where Value: Hashable {}

/// Type-erased access to a ``ToolDescription``-wrapped property, used by ``JSONSchemaEncoder``
/// to read the description and unwrap the value without knowing `Value` generically.
protocol ToolDescriptionProviding {
    var fieldDescription: String { get }
    var erasedWrappedValue: Any { get }
}

extension ToolDescription: ToolDescriptionProviding {
    var erasedWrappedValue: Any { wrappedValue }
}

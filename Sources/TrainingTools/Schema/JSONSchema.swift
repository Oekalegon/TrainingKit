import Foundation

/// A JSON Schema fragment describing a ``TrainingTool``'s `Input` type to a language model.
///
/// Built by ``JSONSchemaEncoder``, never by hand for reflected types — the adapters
/// (`TrainingToolsAnthropic`, `TrainingToolsFoundationModels`) each render this into their
/// provider's own schema representation.
public indirect enum JSONSchema: Sendable, Equatable {
    case string(description: String?)
    case number(description: String?)
    case integer(description: String?)
    case boolean(description: String?)
    case array(items: JSONSchema, description: String?)
    case object(properties: [String: JSONSchema], required: [String], description: String?)
    case enumeration(values: [String], description: String?)

    /// The fragment's own description, if any.
    public var description: String? {
        switch self {
        case let .string(description), let .number(description), let .integer(description),
            let .boolean(description), let .array(_, description), let .object(_, _, description),
            let .enumeration(_, description):
            return description
        }
    }
}

extension JSONSchema: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, description, items, properties, required, enumValues = "enum"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        switch self {
        case .string:
            try container.encode("string", forKey: .type)
        case .number:
            try container.encode("number", forKey: .type)
        case .integer:
            try container.encode("integer", forKey: .type)
        case .boolean:
            try container.encode("boolean", forKey: .type)
        case let .array(items, _):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
        case let .object(properties, required, _):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required.sorted(), forKey: .required)
        case let .enumeration(values, _):
            try container.encode("string", forKey: .type)
            try container.encode(values, forKey: .enumValues)
        }
    }
}

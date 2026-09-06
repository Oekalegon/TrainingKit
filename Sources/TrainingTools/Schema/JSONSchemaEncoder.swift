import Foundation

/// Opt-in conformance for a `String`-backed `enum` used in a tool `Input`, so
/// ``JSONSchemaEncoder`` renders it as ``JSONSchema/enumeration(values:description:)`` (every
/// case's raw value) rather than a generic `string`.
public protocol ToolEnumSchema: CaseIterable, RawRepresentable, Sendable where RawValue == String {}

/// Type-level witness for `Optional<Wrapped>` that works whether the instance in hand is `nil`
/// or not — `Mirror` alone can't recover `Wrapped` from a `nil` `Any`.
private protocol OptionalWitness {
    static var wrappedType: Any.Type { get }
    var unwrapped: Any? { get }
}

extension Optional: OptionalWitness {
    fileprivate static var wrappedType: Any.Type { Wrapped.self }
    fileprivate var unwrapped: Any? { self }
}

/// Builds a ``JSONSchema`` for a ``ToolInput`` type by reflecting over its `example` value.
///
/// This isn't a general-purpose `Codable` → JSON Schema mapper: it only needs to handle the
/// shapes tool inputs actually use (primitives, `Date`, `UUID`, arrays, nested `Codable`
/// structs, ``ToolEnumSchema`` enums, and ``ToolDescription``-wrapped fields), and it favors a
/// best-effort fallback (`.string`) over throwing when it meets something it doesn't recognize —
/// a slightly under-specified schema is fine, dispatch still round-trips through the real
/// `Codable` conformance regardless of what the schema says.
public enum JSONSchemaEncoder {
    /// Builds the ``JSONSchema`` for `Input` by reflecting over ``ToolInput/example``.
    public static func schema<Input: ToolInput>(for type: Input.Type) -> JSONSchema {
        schema(reflecting: Input.example, description: nil)
    }

    private static func schema(reflecting value: Any, description: String?) -> JSONSchema {
        if let provider = value as? ToolDescriptionProviding {
            return schema(reflecting: provider.erasedWrappedValue, description: provider.fieldDescription)
        }

        let mirror = Mirror(reflecting: value)

        if let optionalType = type(of: value) as? OptionalWitness.Type {
            let witness = value as! OptionalWitness
            if let unwrapped = witness.unwrapped {
                return schema(reflecting: unwrapped, description: description)
            }
            return schema(forEmptyOptional: optionalType.wrappedType, description: description)
        }

        switch value {
        case is Bool:
            return .boolean(description: description)
        case is Int, is Int8, is Int16, is Int32, is Int64,
            is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
            return .integer(description: description)
        case is Double, is Float:
            return .number(description: description)
        case is String, is Date, is UUID:
            return .string(description: description)
        default:
            break
        }

        if let cases = enumerationValues(of: value) {
            return .enumeration(values: cases, description: description)
        }

        if mirror.displayStyle == .collection {
            let items = mirror.children.first.map { schema(reflecting: $0.value, description: nil) }
                ?? .string(description: nil)
            return .array(items: items, description: description)
        }

        if mirror.displayStyle == .set {
            let items = mirror.children.first.map { schema(reflecting: $0.value, description: nil) }
                ?? .string(description: nil)
            return .array(items: items, description: description)
        }

        if mirror.displayStyle == .dictionary {
            return .object(properties: [:], required: [], description: description)
        }

        if mirror.displayStyle == .struct || mirror.displayStyle == .class {
            var properties: [String: JSONSchema] = [:]
            var required: [String] = []
            for child in mirror.children {
                guard var label = child.label else { continue }
                if label.hasPrefix("_") { label.removeFirst() }
                properties[label] = schema(reflecting: child.value, description: nil)
                if !isOptional(child.value) {
                    required.append(label)
                }
            }
            return .object(properties: properties, required: required, description: description)
        }

        return .string(description: description)
    }

    /// A `nil` value in `example` loses whatever shape its `Wrapped` type has (`Mirror` can't
    /// recurse into a value that isn't there), so this only infers what's safe to infer from the
    /// type alone: scalars. Anything else — collections, dictionaries, nested structs, `Date`,
    /// `UUID` — falls back to an empty object rather than guessing a scalar type that would be
    /// actively wrong (a `nil` `[String]?` must not schema as `.string`, since a model given that
    /// schema could send a JSON string where the real `Input` decodes an array and fail).
    private static func schema(forEmptyOptional wrappedType: Any.Type, description: String?) -> JSONSchema {
        switch wrappedType {
        case is Bool.Type:
            return .boolean(description: description)
        case is Int.Type, is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type,
            is UInt.Type, is UInt8.Type, is UInt16.Type, is UInt32.Type, is UInt64.Type:
            return .integer(description: description)
        case is Double.Type, is Float.Type:
            return .number(description: description)
        case is String.Type, is Date.Type, is UUID.Type:
            return .string(description: description)
        default:
            return .object(properties: [:], required: [], description: description)
        }
    }

    private static func isOptional(_ value: Any) -> Bool {
        type(of: value) is OptionalWitness.Type
    }

    private static func enumerationValues(of value: Any) -> [String]? {
        guard let schemaEnum = value as? any ToolEnumSchema else { return nil }
        return rawValues(of: schemaEnum)
    }

    private static func rawValues<Enum: ToolEnumSchema>(of value: Enum) -> [String] {
        Enum.allCases.map(\.rawValue)
    }
}

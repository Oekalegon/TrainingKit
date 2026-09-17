import Foundation

/// A ``TrainingTool``'s `Input` type: `Codable` for dispatch, plus one concrete `example` value
/// that ``JSONSchemaEncoder`` reflects over to build the tool's ``JSONSchema``.
///
/// There's no zero-argument `init` requirement on `Input` itself — reflection needs a real
/// instance to walk, and `example` is that instance. Optional fields should generally be
/// non-`nil` in `example` and array fields non-empty, so the encoder can infer their element
/// schema — this matters most for `Optional` collections, dictionaries, and nested `Codable`
/// structs, where a `nil`/empty example doesn't just lose detail, it produces a schema of the
/// *wrong* JSON type (e.g. a `nil` `[String]?` schemas as `.string`, not `.array`), which can
/// make a model-generated argument fail to decode. `Bool?`/`Int?`/`Double?` are safe either way
/// since ``JSONSchemaEncoder`` can infer their scalar type without a concrete value.
public protocol ToolInput: Codable, Sendable {
    static var example: Self { get }
}

/// A ``TrainingTool`` with no input, e.g. `list_races`.
public struct NoToolInput: ToolInput {
    public static let example = NoToolInput()
    public init() {}
}

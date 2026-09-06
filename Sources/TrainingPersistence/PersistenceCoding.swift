import Foundation

/// The single place every model record encodes/decodes its Core value-type payload, so all five
/// records agree on the same `JSONEncoder`/`JSONDecoder` configuration rather than each
/// constructing its own.
enum PersistenceCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

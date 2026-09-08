import Foundation

/// The single place every model record encodes/decodes its Core value-type payload, so all five
/// records agree on the same `JSONEncoder`/`JSONDecoder` configuration rather than each
/// constructing its own.
enum PersistenceCoding {
    /// `FitnessMetrics.monotony`/`.strain` can legitimately be `.nan` (a perfectly flat week —
    /// see that type's doc comment), which the default `.throw` strategy would reject outright.
    private static let nonConformingFloatSentinels = (positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: nonConformingFloatSentinels.positiveInfinity,
            negativeInfinity: nonConformingFloatSentinels.negativeInfinity,
            nan: nonConformingFloatSentinels.nan
        )
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: nonConformingFloatSentinels.positiveInfinity,
            negativeInfinity: nonConformingFloatSentinels.negativeInfinity,
            nan: nonConformingFloatSentinels.nan
        )
        return try decoder.decode(type, from: data)
    }
}

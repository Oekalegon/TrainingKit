import Foundation

/// The intensity of one planned or performed activity, with how it was derived.
///
/// ``source`` mirrors the estimated-versus-measured distinction used for TRIMP, so a UI can label
/// both the same way.
public struct IntensityAssessment: Sendable, Codable, Hashable {
    /// Where the assessment comes from.
    public enum Source: Sendable, Codable, Hashable {
        /// Derived from a ``StructuredWorkout``'s steps; no sensor data involved.
        case planned
        /// Derived from recorded sensor data.
        case measured
        /// A planned category confirmed or adjusted by recorded sensor data.
        case blended
    }

    /// How much the result should be trusted.
    public enum Confidence: Int, Sendable, Codable, Hashable, Comparable {
        /// Little to go on: no usable heart rate, sparse samples, or only perceived exertion.
        case low = 0
        /// One good source, or two that couldn't be compared.
        case medium = 1
        /// Independent sources agree: a plan whose targets all resolved and heart rate that confirms it.
        case high = 2

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The resulting category.
    public let category: IntensityCategory
    /// Where the assessment comes from.
    public let source: Source
    /// How much the result should be trusted.
    public let confidence: Confidence
    /// Time in zones 4–5 that counted towards the category.
    public let hardSeconds: TimeInterval
    /// Time in zone 3 that counted towards the category.
    public let moderateSeconds: TimeInterval

    /// Creates an assessment.
    ///
    /// - Parameters:
    ///   - category: The resulting category.
    ///   - source: Where the assessment comes from.
    ///   - confidence: How much the result should be trusted.
    ///   - hardSeconds: Time in zones 4–5 that counted towards the category.
    ///   - moderateSeconds: Time in zone 3 that counted towards the category.
    public init(
        category: IntensityCategory,
        source: Source,
        confidence: Confidence,
        hardSeconds: TimeInterval,
        moderateSeconds: TimeInterval
    ) {
        self.category = category
        self.source = source
        self.confidence = confidence
        self.hardSeconds = hardSeconds
        self.moderateSeconds = moderateSeconds
    }
}

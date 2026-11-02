import Foundation

/// The steps a template parameter moves in (MVP5-155): the values worth offering for a duration, a
/// distance or a count, so a range of 15 to 60 minutes gives 15, 20, 25 … and not every second.
///
/// The step grows with the value, so a short value is fine-grained and a long one is not. A value belongs
/// to the band it falls in, so a band's lower bound is inclusive:
///
/// | Unit | Value | Step |
/// |---|---|---|
/// | ``ParameterUnit/minutes`` (in seconds) | under 1 min | 5 s |
/// | | 1 to under 5 min | 30 s |
/// | | 5 to under 10 min | 1 min |
/// | | 10 to under 100 min | 5 min |
/// | | 100 min and over | 10 min |
/// | ``ParameterUnit/meters`` | under 200 m | 50 m |
/// | | 200 to under 400 m | 100 m |
/// | | 400 m to under 1.6 km | 400 m |
/// | | 1.6 to under 3 km | 800 m |
/// | | 3 to under 10 km | 1 km |
/// | | 10 km and over | 5 km |
/// | ``ParameterUnit/count`` | any | 1 |
///
/// A duration parameter holds its value in seconds, whatever its unit is called (see the built-in templates).
public enum ParameterGrid {
    /// The step at `value`.
    ///
    /// - Parameters:
    ///   - value: The parameter value: seconds for ``ParameterUnit/minutes``, meters for ``ParameterUnit/meters``.
    ///   - unit: The parameter's unit.
    /// - Returns: The step in the same unit as `value`.
    public static func step(at value: Double, unit: ParameterUnit) -> Double {
        switch unit {
        case .minutes: value < 60 ? 5 : value < 300 ? 30 : value < 600 ? 60 : value < 6_000 ? 300 : 600
        case .meters: value < 200 ? 50 : value < 400 ? 100 : value < 1_600 ? 400 : value < 3_000 ? 800 : value < 10_000 ? 1_000 : 5_000
        case .count: 1
        }
    }

    /// The values where the step changes, ascending.
    private static func edges(of unit: ParameterUnit) -> [Double] {
        switch unit {
        case .minutes: [60, 300, 600, 6_000]
        case .meters: [200, 400, 1_600, 3_000, 10_000]
        case .count: []
        }
    }

    /// The grid values inside `range`, ascending.
    ///
    /// The first value is the first multiple of the step that is not below the range's start, and each next one
    /// is a step further, or the start of the next band when that comes first (1.6 km, 2.4 km, 3 km, 4 km). A range that
    /// holds no grid value gives its lower bound.
    ///
    /// - Parameters:
    ///   - range: The parameter's range.
    ///   - unit: The parameter's unit.
    /// - Returns: The values, at least one.
    public static func values(in range: ClosedRange<Double>, unit: ParameterUnit) -> [Double] {
        let epsilon = 1e-9
        let edges = edges(of: unit)
        /// `candidate`, or the first band start between `value` and it.
        func capped(_ candidate: Double, after value: Double, inclusive: Bool) -> Double {
            edges.first { (inclusive ? $0 >= value - epsilon : $0 > value + epsilon) && $0 <= candidate + epsilon } ?? candidate
        }
        let first = step(at: range.lowerBound, unit: unit)
        var value = capped((range.lowerBound / first - epsilon).rounded(.up) * first, after: range.lowerBound, inclusive: true)
        var values: [Double] = []
        while value <= range.upperBound + epsilon, values.count < 10_000 {
            values.append(value)
            value = capped(value + step(at: value, unit: unit), after: value, inclusive: false)
        }
        return values.isEmpty ? [range.lowerBound] : values
    }

    /// `value` moved to the nearest grid value (the lower one on a tie).
    ///
    /// - Parameters:
    ///   - value: The value to snap, in the unit's base (seconds for ``ParameterUnit/minutes``, meters for ``ParameterUnit/meters``).
    ///   - unit: The parameter's unit.
    /// - Returns: A value ``values(in:unit:)`` would list; a band's start is a candidate, so 2,950 m snaps to 3,000 m.
    public static func snapped(_ value: Double, unit: ParameterUnit) -> Double {
        let reach = 2 * step(at: value, unit: unit)
        let candidates = values(in: max(0, value - reach)...(value + reach), unit: unit)
        return candidates.reduce(candidates[0]) { abs($1 - value) < abs($0 - value) - 1e-9 ? $1 : $0 }
    }
}

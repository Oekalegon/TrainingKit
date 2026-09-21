import Foundation

extension Activity {
    /// Combines two back-to-back activities — one session accidentally recorded in two pieces —
    /// into a single activity spanning both (see ``OverlapRecommendation/join``).
    ///
    /// The result has a new `id` and a `.manual` source. It's a derived activity, not either
    /// original's record: the originals keep their own sources and stay in the store, linked to
    /// this one via ``ActivityStore/saveJoin(_:components:replacing:)``.
    ///
    /// - The span runs from the earlier ``start`` to the later end, so the (short) gap between the
    ///   two pieces counts as part of the session. That keeps ``dateRange`` contiguous, but a load
    ///   that falls back to duration × RPE (see ``DurationRPECalculator``) includes the gap, by up
    ///   to ``ActivityOverlapThresholds/joinGapTolerance``; heart-rate TRIMP skips gaps over 60 s.
    ///   When the pieces overlap slightly, ``distanceMeters`` is a plain sum and so counts the
    ///   overlapped stretch twice.
    /// - ``heartRate`` and ``speed`` samples are concatenated in time order; ``distanceMeters``
    ///   sums whichever sides report one.
    /// - ``elevation`` sums gain and loss and widens min/max; ``geographicBounds`` is the union.
    /// - ``cadence`` min/max widen; mean and median are duration-weighted averages of the two
    ///   pieces' values — the raw stream isn't kept, so the merged median is an approximation.
    /// - ``perceivedExertion`` is the duration-weighted average of whichever sides have one.
    /// - ``sport`` is the longer piece's. ``linkedPlanID`` is the earlier piece's, else the later's:
    ///   if the pieces were reconciled to two different plans, the later piece's plan loses its
    ///   match.
    ///
    /// - Parameters:
    ///   - a: One piece.
    ///   - b: The other piece, in either order.
    ///   - id: The combined activity's id; a new one by default. Pass an existing joined activity's
    ///     id to rebuild it in place (see ``TrainingModel/importActivities(from:asOf:)``).
    /// - Returns: The combined activity.
    public static func joined(_ a: Activity, _ b: Activity, id: UUID = UUID()) -> Activity {
        let (first, second) = a.start <= b.start ? (a, b) : (b, a)
        let end = max(first.dateRange.upperBound, second.dateRange.upperBound)
        let weightA = max(first.duration, 0)
        let weightB = max(second.duration, 0)
        let totalWeight = weightA + weightB

        func weighted(_ x: Double, _ y: Double) -> Double {
            totalWeight > 0 ? (x * weightA + y * weightB) / totalWeight : (x + y) / 2
        }

        let distance: Double? = (first.distanceMeters == nil && second.distanceMeters == nil)
            ? nil : (first.distanceMeters ?? 0) + (second.distanceMeters ?? 0)

        let elevation: ElevationStats? = switch (first.elevation, second.elevation) {
        case let (x?, y?):
            ElevationStats(
                gainMeters: x.gainMeters + y.gainMeters, lossMeters: x.lossMeters + y.lossMeters,
                minMeters: min(x.minMeters, y.minMeters), maxMeters: max(x.maxMeters, y.maxMeters)
            )
        case let (x?, nil): x
        case let (nil, y?): y
        case (nil, nil): nil
        }

        let cadence: CadenceStats? = switch (first.cadence, second.cadence) {
        case let (x?, y?):
            CadenceStats(
                min: min(x.min, y.min), max: max(x.max, y.max),
                mean: weighted(x.mean, y.mean), median: weighted(x.median, y.median)
            )
        case let (x?, nil): x
        case let (nil, y?): y
        case (nil, nil): nil
        }

        let bounds: GeographicBounds? = switch (first.geographicBounds, second.geographicBounds) {
        case let (x?, y?):
            GeographicBounds(
                minLatitude: min(x.minLatitude, y.minLatitude), maxLatitude: max(x.maxLatitude, y.maxLatitude),
                minLongitude: min(x.minLongitude, y.minLongitude), maxLongitude: max(x.maxLongitude, y.maxLongitude)
            )
        case let (x?, nil): x
        case let (nil, y?): y
        case (nil, nil): nil
        }

        let exertion: Int? = switch (first.perceivedExertion, second.perceivedExertion) {
        case let (x?, y?): Int(weighted(Double(x), Double(y)).rounded())
        case let (x?, nil): x
        case let (nil, y?): y
        case (nil, nil): nil
        }

        return Activity(
            id: id,
            source: .manual,
            sport: weightB > weightA ? second.sport : first.sport,
            start: first.start,
            duration: end.timeIntervalSince(first.start),
            distanceMeters: distance,
            heartRate: (first.heartRate + second.heartRate).sorted { $0.time < $1.time },
            speed: (first.speed + second.speed).sorted { $0.time < $1.time },
            elevation: elevation,
            cadence: cadence,
            geographicBounds: bounds,
            perceivedExertion: exertion,
            linkedPlanID: first.linkedPlanID ?? second.linkedPlanID
        )
    }

    /// Combines any number of pieces, earliest first, by folding ``joined(_:_:id:)`` — so three
    /// pieces of one session become one activity, not a join of a join.
    ///
    /// - Parameters:
    ///   - pieces: The pieces, in any order.
    ///   - id: The combined activity's id; a new one by default.
    /// - Returns: The combined activity, or `nil` if `pieces` has fewer than two.
    public static func joined(_ pieces: [Activity], id: UUID = UUID()) -> Activity? {
        guard pieces.count >= 2 else { return nil }
        let sorted = pieces.sorted { $0.start < $1.start }
        var result = sorted[0]
        for (offset, next) in sorted.dropFirst().enumerated() {
            let isLast = offset == sorted.count - 2
            result = joined(result, next, id: isLast ? id : UUID())
        }
        return result
    }
}

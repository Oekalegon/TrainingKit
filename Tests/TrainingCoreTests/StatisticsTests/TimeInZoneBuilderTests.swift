import Foundation
import Testing
@testable import TrainingCore

@Suite("TimeInZoneBuilder")
struct TimeInZoneBuilderTests {
    /// Karvonen zone edge ratios: z1 [0.50, 0.60), z2 [0.60, 0.70), z3 [0.70, 0.80), z4 [0.80,
    /// 0.90), z5 [0.90, 1.00].
    private let karvonenBoundaries: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90, 1.00]

    @Test("a segment ascending across three boundaries splits proportionally into four zones")
    func splitAcrossMultipleBoundariesAscending() {
        let segment = HeartRateSegmentIterator.Segment(duration: 300, startRatio: 0.55, endRatio: 0.85)
        let result = TimeInZoneBuilder.split(segment, boundaries: karvonenBoundaries)

        #expect(result.map(\.zone) == [1, 2, 3, 4])
        for (index, expectedDuration) in [50.0, 100.0, 100.0, 50.0].enumerated() {
            #expect(abs(result[index].duration - expectedDuration) < 0.001)
        }
        #expect(abs(result.reduce(0) { $0 + $1.duration } - segment.duration) < 0.001)
    }

    @Test("a segment descending across three boundaries splits proportionally, zones in reverse order")
    func splitAcrossMultipleBoundariesDescending() {
        let segment = HeartRateSegmentIterator.Segment(duration: 300, startRatio: 0.85, endRatio: 0.55)
        let result = TimeInZoneBuilder.split(segment, boundaries: karvonenBoundaries)

        #expect(result.map(\.zone) == [4, 3, 2, 1])
        for (index, expectedDuration) in [50.0, 100.0, 100.0, 50.0].enumerated() {
            #expect(abs(result[index].duration - expectedDuration) < 0.001)
        }
        #expect(abs(result.reduce(0) { $0 + $1.duration } - segment.duration) < 0.001)
    }

    @Test("zone(for:) clamps below the lowest boundary to zone 0")
    func zoneClampsBelowLowestBoundaryToZero() {
        #expect(TimeInZoneBuilder.zone(for: 0.2, boundaries: karvonenBoundaries) == 0)
    }

    @Test("zone(for:) at an exact boundary lands in the upper zone")
    func zoneAtExactBoundaryLandsInUpperZone() {
        #expect(TimeInZoneBuilder.zone(for: 0.50, boundaries: karvonenBoundaries) == 1)
        #expect(TimeInZoneBuilder.zone(for: 0.60, boundaries: karvonenBoundaries) == 2)
    }

    @Test("zone(for:) clamps at and above the top boundary to zone 5")
    func zoneClampsAtOrAboveTopBoundaryToFive() {
        #expect(TimeInZoneBuilder.zone(for: 1.00, boundaries: karvonenBoundaries) == 5)
        #expect(TimeInZoneBuilder.zone(for: 1.15, boundaries: karvonenBoundaries) == 5)
    }
}

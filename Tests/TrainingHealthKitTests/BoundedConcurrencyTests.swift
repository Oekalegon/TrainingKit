import Testing
@testable import TrainingHealthKit

@Suite("mapBounded")
struct BoundedConcurrencyTests {
    @Test("processes every item even when maxConcurrent is smaller than the item count")
    func processesEveryItem() async throws {
        let items = Array(0..<50)
        let results = try await mapBounded(items, maxConcurrent: 4) { $0 * 2 }
        #expect(Set(results) == Set(items.map { $0 * 2 }))
        #expect(results.count == items.count)
    }

    @Test("never runs more than maxConcurrent transforms at once")
    func boundsConcurrency() async throws {
        let tracker = ConcurrencyTracker()
        let maxConcurrent = 3
        _ = try await mapBounded(Array(0..<20), maxConcurrent: maxConcurrent) { _ in
            let current = await tracker.enter()
            #expect(current <= maxConcurrent)
            try await Task.sleep(nanoseconds: 1_000_000)
            await tracker.exit()
            return 0
        }
        await #expect(tracker.peak() <= maxConcurrent)
    }

    @Test("a thrown error propagates out of mapBounded")
    func propagatesError() async {
        struct MarkerError: Error {}
        await #expect(throws: MarkerError.self) {
            _ = try await mapBounded(Array(0..<10), maxConcurrent: 2) { value in
                if value == 5 { throw MarkerError() }
                return value
            }
        }
    }

    @Test("a non-positive maxConcurrent still makes progress, treated as 1")
    func nonPositiveMaxConcurrentStillProgresses() async throws {
        let results = try await mapBounded([1, 2, 3], maxConcurrent: 0) { $0 }
        #expect(results.sorted() == [1, 2, 3])
    }

    @Test("an empty input returns an empty result without hanging")
    func emptyInput() async throws {
        let results = try await mapBounded([Int](), maxConcurrent: 4) { $0 }
        #expect(results.isEmpty)
    }
}

/// Tracks how many concurrent `enter()`/`exit()` pairs are open at once, for asserting bounded
/// concurrency without any HealthKit/HKWorkout involvement.
private actor ConcurrencyTracker {
    private var current = 0
    private var maxObserved = 0

    func enter() -> Int {
        current += 1
        maxObserved = max(maxObserved, current)
        return current
    }

    func exit() {
        current -= 1
    }

    func peak() -> Int {
        maxObserved
    }
}

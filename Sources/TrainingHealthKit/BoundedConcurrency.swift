/// Applies `transform` to each element of `items` concurrently, with at most `maxConcurrent`
/// transforms in flight at once. Results are collected in whatever order their tasks complete, not
/// necessarily the order of `items`.
///
/// Used by ``HealthKitActivityImporter`` to bound how many workouts are fetched concurrently during
/// a full historical import: launching one unbounded task per workout floods both HealthKit's query
/// queue and any serialized store behind `activityStore`, which in practice can make the import
/// appear to hang indefinitely — see `HealthKitActivityImporter.importActivities(since:)`.
///
/// A thrown error from any `transform` call propagates out (cancelling every other in-flight task,
/// per `withThrowingTaskGroup`'s own semantics) exactly as an unbounded task group would — this
/// function only bounds concurrency, it doesn't change failure handling. A caller that wants one
/// failed item to not abort the rest should catch inside `transform` itself and return a fallback
/// value instead of throwing.
///
/// - Parameters:
///   - items: The elements to process.
///   - maxConcurrent: The maximum number of `transform` calls in flight at once; treated as `1` if
///     given a non-positive value.
///   - transform: Applied to each element of `items`, potentially concurrently with other calls.
/// - Returns: One result per element of `items`, in completion order.
func mapBounded<Element: Sendable, Result: Sendable>(
    _ items: [Element],
    maxConcurrent: Int,
    _ transform: @escaping @Sendable (Element) async throws -> Result
) async throws -> [Result] {
    try await withThrowingTaskGroup(of: Result.self) { group in
        var remaining = items.makeIterator()
        func addNextTask() {
            guard let item = remaining.next() else { return }
            group.addTask { try await transform(item) }
        }
        for _ in 0..<Swift.max(1, maxConcurrent) {
            addNextTask()
        }
        var results: [Result] = []
        results.reserveCapacity(items.count)
        for try await result in group {
            results.append(result)
            addNextTask()
        }
        return results
    }
}

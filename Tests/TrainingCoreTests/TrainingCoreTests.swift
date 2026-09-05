import Testing
@testable import TrainingCore

@Suite("TrainingCore")
struct TrainingCoreTests {
    @Test("package scaffold builds")
    func scaffoldBuilds() {
        #expect(Bool(true))
    }
}

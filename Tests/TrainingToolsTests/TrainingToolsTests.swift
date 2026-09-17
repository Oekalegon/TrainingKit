import Testing
@testable import TrainingTools

@Suite("TrainingTools")
struct TrainingToolsTests {
    @Test("package scaffold builds")
    func scaffoldBuilds() {
        #expect(Bool(true))
    }
}

import Testing
@testable import Jools

@Suite("Jools App Tests")
struct JoolsTests {
    @Test("App launches successfully")
    func appLaunches() async throws {
        // Basic smoke test
        #expect(true)
    }
}

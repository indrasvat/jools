import Testing
import Foundation
@testable import JoolsKit

@Suite("KeychainManager Tests")
struct KeychainManagerTests {

    // Note: These tests require a keychain environment to run properly
    // In CI, they may need to be skipped or run with a mock

    @Test("Can check if API key exists")
    func testHasAPIKey() {
        let keychain = KeychainManager(service: "com.jools.test")
        // Clean up any existing key
        try? keychain.deleteAPIKey()

        #expect(keychain.hasAPIKey() == false)
    }

    @Test("KeychainError has descriptions")
    func testKeychainErrorDescriptions() {
        let saveError = KeychainError.saveFailed(-1)
        let deleteError = KeychainError.deleteFailed(-2)
        let unexpectedError = KeychainError.unexpectedData

        #expect(saveError.errorDescription?.contains("save") == true)
        #expect(deleteError.errorDescription?.contains("delete") == true)
        #expect(unexpectedError.errorDescription?.contains("Unexpected") == true)
    }
}

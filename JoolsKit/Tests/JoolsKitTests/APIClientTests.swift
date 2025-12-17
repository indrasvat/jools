import Testing
import Foundation
@testable import JoolsKit

@Suite("APIClient Tests")
struct APIClientTests {

    @Test("Decodes source list correctly")
    func testDecodeSourceList() throws {
        let json = """
        {
            "sources": [
                {
                    "name": "sources/github/owner/repo",
                    "id": "github/owner/repo",
                    "githubRepo": {
                        "owner": "owner",
                        "repo": "repo"
                    }
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(
            PaginatedResponse<SourceDTO>.self,
            from: json.data(using: .utf8)!
        )

        #expect(response.allItems.count == 1)
        #expect(response.allItems[0].id == "github/owner/repo")
        #expect(response.allItems[0].githubRepo.owner == "owner")
        #expect(response.allItems[0].githubRepo.repo == "repo")
    }

    @Test("Decodes session correctly")
    func testDecodeSession() throws {
        let json = """
        {
            "name": "sessions/123456789",
            "id": "123456789",
            "title": "Test Session",
            "prompt": "Fix the bug",
            "state": "RUNNING",
            "sourceContext": {
                "source": "sources/github/owner/repo",
                "githubRepoContext": {
                    "startingBranch": "main"
                }
            },
            "automationMode": "AUTO_CREATE_PR",
            "requirePlanApproval": true
        }
        """

        let decoder = JSONDecoder()
        let session = try decoder.decode(SessionDTO.self, from: json.data(using: .utf8)!)

        #expect(session.id == "123456789")
        #expect(session.title == "Test Session")
        #expect(session.prompt == "Fix the bug")
        #expect(session.state == "RUNNING")
        #expect(session.requirePlanApproval == true)
    }

    @Test("Decodes activity correctly")
    func testDecodeActivity() throws {
        let json = """
        {
            "name": "sessions/123/activities/456",
            "id": "456",
            "type": "AGENT_MESSAGED",
            "content": {
                "message": "I'll help you fix that bug"
            }
        }
        """

        let decoder = JSONDecoder()
        let activity = try decoder.decode(ActivityDTO.self, from: json.data(using: .utf8)!)

        #expect(activity.id == "456")
        #expect(activity.type == "AGENT_MESSAGED")
        #expect(activity.content?.message == "I'll help you fix that bug")
    }

    @Test("SessionState enum has correct raw values")
    func testSessionStateRawValues() {
        #expect(SessionState.running.rawValue == "RUNNING")
        #expect(SessionState.awaitingUserInput.rawValue == "AWAITING_USER_INPUT")
        #expect(SessionState.completed.rawValue == "COMPLETED")
    }

    @Test("SessionState isActive returns correct values")
    func testSessionStateIsActive() {
        #expect(SessionState.running.isActive == true)
        #expect(SessionState.queued.isActive == true)
        #expect(SessionState.awaitingUserInput.isActive == true)
        #expect(SessionState.completed.isActive == false)
        #expect(SessionState.failed.isActive == false)
    }

    @Test("CreateSessionRequest encodes correctly")
    func testCreateSessionRequestEncoding() throws {
        let request = CreateSessionRequest(
            prompt: "Fix the login bug",
            sourceContext: SourceContextDTO(
                source: "sources/github/owner/repo",
                githubRepoContext: GitHubRepoContextDTO(startingBranch: "main")
            ),
            title: "Login Bug Fix",
            automationMode: "AUTO_CREATE_PR",
            requirePlanApproval: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["prompt"] as? String == "Fix the login bug")
        #expect(json["title"] as? String == "Login Bug Fix")
        #expect(json["requirePlanApproval"] as? Bool == true)
    }

    @Test("NetworkError has correct descriptions")
    func testNetworkErrorDescriptions() {
        #expect(NetworkError.unauthorized.errorDescription?.contains("API key") == true)
        #expect(NetworkError.rateLimited.errorDescription?.contains("limit") == true)
        #expect(NetworkError.serverError(500).errorDescription?.contains("500") == true)
    }

    @Test("NetworkError isRetryable returns correct values")
    func testNetworkErrorIsRetryable() {
        #expect(NetworkError.serverError(500).isRetryable == true)
        #expect(NetworkError.rateLimited.isRetryable == true)
        #expect(NetworkError.unauthorized.isRetryable == false)
        #expect(NetworkError.notFound.isRetryable == false)
    }
}

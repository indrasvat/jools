import Testing
import Foundation
@testable import JoolsKit

@Suite("APIClient Tests", .serialized)
struct APIClientTests {
    @Test("Send message succeeds on empty HTTP 200 body")
    func sendMessageSucceedsOnEmptyBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestCount = 0

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            #expect(request.url?.path == "/v1alpha/sessions/123:sendMessage")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let keychain = KeychainManager(service: "com.indrasvat.jools.tests.\(UUID().uuidString)")
        try keychain.saveAPIKey("test-key")
        defer { try? keychain.deleteAPIKey() }

        let client = APIClient(
            keychain: keychain,
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.com/v1alpha/")!
        )

        try await client.sendMessage(sessionId: "123", message: "hello")
    }

    @Test("listActivities sends compact fields= mask by default")
    func listActivitiesSendsCompactFieldsMask() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestCount = 0

        let keychain = KeychainManager(service: "com.indrasvat.jools.tests.\(UUID().uuidString)")
        try keychain.saveAPIKey("test-key")
        defer { try? keychain.deleteAPIKey() }

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.requestCount += 1
            let query = request.url?.query ?? ""
            #expect(query.contains("fields="))
            // The mask MUST omit unidiffPatch — that's the bloat field
            // we measured at 94 MB per activity on real sessions.
            #expect(query.contains("unidiffPatch") == false)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"activities\":[]}".utf8)
            )
        }

        let client = APIClient(
            keychain: keychain,
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.com/v1alpha/")!
        )

        _ = try await client.listAllActivities(sessionId: "s1")
        #expect(MockURLProtocol.requestCount >= 1)
    }

    @Test("listActivities sends no fields= when mask is nil (getActivity lazy-fetch path)")
    func listActivitiesOmitsFieldsWhenNil() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestCount = 0

        let keychain = KeychainManager(service: "com.indrasvat.jools.tests.\(UUID().uuidString)")
        try keychain.saveAPIKey("test-key")
        defer { try? keychain.deleteAPIKey() }

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.requestCount += 1
            let query = request.url?.query ?? ""
            #expect(query.contains("fields=") == false)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"activities\":[]}".utf8)
            )
        }

        let client = APIClient(
            keychain: keychain,
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.com/v1alpha/")!
        )

        _ = try await client.listAllActivities(sessionId: "s1", fields: nil)
        #expect(MockURLProtocol.requestCount >= 1)
    }

    @Test("Falls back when activity createTime filtering is unsupported")
    func listActivitiesFallsBackWhenCreateTimeIsRejected() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestCount = 0

        let keychain = KeychainManager(service: "com.indrasvat.jools.tests.\(UUID().uuidString)")
        try keychain.saveAPIKey("test-key")
        defer { try? keychain.deleteAPIKey() }

        let cutoff = try #require(ISO8601DateFormatter().date(from: "2026-04-05T22:00:00Z"))

        let fallbackResponse = """
        {
          "activities": [
            {
              "name": "sessions/123/activities/old-activity",
              "id": "old-activity",
              "createTime": "2026-04-05T21:59:00Z",
              "userMessaged": { "userMessage": "old" }
            },
            {
              "name": "sessions/123/activities/new-activity",
              "id": "new-activity",
              "createTime": "2026-04-05T22:05:00Z",
              "agentMessaged": { "agentMessage": "new" }
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.requestCount += 1
            let query = request.url?.query ?? ""

            if MockURLProtocol.requestCount == 1 {
                #expect(query.contains("createTime="))
                let data = """
                {
                  "error": {
                    "code": 400,
                    "message": "Unknown name \\"createTime\\": Cannot bind query parameter. Field 'createTime' could not be found in request message.",
                    "status": "INVALID_ARGUMENT"
                  }
                }
                """.data(using: .utf8)!

                return (
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                    data
                )
            }

            #expect(query.contains("createTime=") == false)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(fallbackResponse.utf8)
            )
        }

        let client = APIClient(
            keychain: keychain,
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.com/v1alpha/")!
        )

        let activities = try await client.listAllActivities(
            sessionId: "123",
            pageSize: 100,
            createTime: cutoff
        )

        #expect(MockURLProtocol.requestCount == 2)
        #expect(activities.map(\.id) == ["new-activity"])
    }

    @Test("Decodes reopened session fixture")
    func decodeReopenedSessionFixture() throws {
        let session = try decodeFixture("session_reopened", as: SessionDTO.self)

        #expect(session.id == "1537655633111249109")
        #expect(session.state == "IN_PROGRESS")
        #expect(session.requirePlanApproval == true)
        #expect(session.sourceContext?.githubRepoContext?.startingBranch == "main")
    }

    @Test("Decodes resumed activity timeline fixture")
    func decodeResumedActivityTimelineFixture() throws {
        let response = try decodeFixture("activities_resumed_follow_up", as: PaginatedResponse<ActivityDTO>.self)
        let activities = response.allItems

        #expect(activities.count == 4)
        #expect(activities[0].activityType == .userMessaged)
        #expect(activities[0].userMessaged?.userMessage == "Thanks. One follow-up: what are the main data models?")
        #expect(activities[1].activityType == .planGenerated)
        #expect(activities[1].planGenerated?.plan?.steps?.count == 2)
        #expect(activities[2].progressUpdated?.title == "Provide the summary to the user")
        #expect(activities[3].agentMessaged?.agentMessage == "The models are ItemBase, Story, and Comment.")
    }

    @Test("Decodes progress artifacts fixture")
    func decodeProgressArtifactsFixture() throws {
        let activity = try decodeFixture("activity_progress_with_artifacts", as: ActivityDTO.self)

        #expect(activity.activityType == .progressUpdated)
        #expect(activity.progressUpdated?.title == "Running the focused test suite")
        #expect(activity.artifacts?.count == 2)
        #expect(activity.content.bashCommands.first?.command == "swift test --filter PollingServiceTests")
        #expect(activity.content.bashCommands.first?.isLikelyFailure == false)
        #expect(activity.content.artifacts?.compactMap { $0.changeSet?.gitPatch?.baseCommitId }.first == "cc774b08299fcbac88622cd6b0470bbd352bb5d8")
    }

    @Test("Decodes completed activity change-set fixture")
    func decodeCompletedActivityFixture() throws {
        let activity = try decodeFixture("activity_session_completed", as: ActivityDTO.self)

        #expect(activity.activityType == .sessionCompleted)
        #expect(activity.sessionCompleted?.summary == "Implemented the polling changes and verified the end-to-end flow.")
        let patch = activity.artifacts?.compactMap { $0.changeSet?.gitPatch }.first
        #expect(patch?.suggestedCommitMessage == "fix(chat): tighten session sync recovery")
        #expect(patch?.changedFiles == ["Jools/Features/Chat/ChatView.swift"])
    }

    @Test("NetworkError has correct descriptions")
    func networkErrorDescriptions() {
        #expect(NetworkError.unauthorized.errorDescription?.contains("API key") == true)
        #expect(NetworkError.rateLimited.errorDescription?.contains("limit") == true)
        #expect(NetworkError.serverError(500).errorDescription?.contains("500") == true)
    }

    @Test("NetworkError isRetryable returns correct values")
    func networkErrorRetryability() {
        #expect(NetworkError.serverError(500).isRetryable == true)
        #expect(NetworkError.rateLimited.isRetryable == true)
        #expect(NetworkError.unauthorized.isRetryable == false)
        #expect(NetworkError.notFound.isRetryable == false)
    }
}

private func decodeFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    let data = try Data(contentsOf: url)
    return try makeDecoder().decode(T.self, from: data)
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode date: \(dateString)"
        )
    }
    return decoder
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

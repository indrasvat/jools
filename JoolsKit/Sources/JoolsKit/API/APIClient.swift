import Foundation

/// Actor-based API client for the Jules API
public actor APIClient {
    // MARK: - Properties

    private let session: URLSession
    private let keychain: KeychainManager
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Initialization

    public init(
        keychain: KeychainManager,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://jules.googleapis.com/v1alpha/")!
    ) {
        self.keychain = keychain
        self.session = session
        self.baseURL = baseURL

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Generic Request

    private func request<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        guard let apiKey = keychain.loadAPIKey() else {
            throw NetworkError.noAPIKey
        }

        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw NetworkError.encodingFailed
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    private func requestEmpty(
        _ endpoint: Endpoint,
        body: (any Encodable & Sendable)? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint, body: body)
    }

    private func handleStatusCode(_ code: Int, data: Data) throws {
        switch code {
        case 200..<300:
            return
        case 401:
            throw NetworkError.unauthorized
        case 403:
            throw NetworkError.forbidden
        case 404:
            throw NetworkError.notFound
        case 429:
            throw NetworkError.rateLimited
        case 500..<600:
            throw NetworkError.serverError(code)
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw NetworkError.apiError(errorResponse.error.message)
            }
            throw NetworkError.unknown(code)
        }
    }

    // MARK: - Sources

    /// List all connected sources (repositories)
    public func listSources(pageToken: String? = nil) async throws -> PaginatedResponse<SourceDTO> {
        try await request(.sources(pageToken: pageToken))
    }

    /// Get a specific source by ID
    public func getSource(id: String) async throws -> SourceDTO {
        try await request(.source(id: id))
    }

    // MARK: - Sessions

    /// List all sessions
    public func listSessions(pageSize: Int = 20, pageToken: String? = nil) async throws -> PaginatedResponse<SessionDTO> {
        try await request(.sessions(pageSize: pageSize, pageToken: pageToken))
    }

    /// Get a specific session by ID
    public func getSession(id: String) async throws -> SessionDTO {
        try await request(.session(id: id))
    }

    /// Create a new session
    public func createSession(_ request: CreateSessionRequest) async throws -> SessionDTO {
        try await self.request(.createSession, body: request)
    }

    /// Delete a session
    public func deleteSession(id: String) async throws {
        try await requestEmpty(.deleteSession(id: id))
    }

    /// Approve the pending plan for a session
    public func approvePlan(sessionId: String) async throws {
        try await requestEmpty(.approvePlan(sessionId: sessionId))
    }

    /// Send a message to a session
    public func sendMessage(sessionId: String, message: String) async throws {
        let body = SendMessageRequest(prompt: message)
        try await requestEmpty(.sendMessage(sessionId: sessionId), body: body)
    }

    // MARK: - Activities

    /// List activities in a session
    public func listActivities(
        sessionId: String,
        pageSize: Int = 30,
        pageToken: String? = nil
    ) async throws -> PaginatedResponse<ActivityDTO> {
        try await request(.activities(sessionId: sessionId, pageSize: pageSize, pageToken: pageToken))
    }

    /// Get a specific activity
    public func getActivity(sessionId: String, activityId: String) async throws -> ActivityDTO {
        try await request(.activity(sessionId: sessionId, activityId: activityId))
    }

    // MARK: - Validation

    /// Validate that the configured API key is valid
    public func validateAPIKey() async throws -> Bool {
        do {
            let _: PaginatedResponse<SourceDTO> = try await request(.sources(pageToken: nil))
            return true
        } catch NetworkError.unauthorized {
            return false
        } catch NetworkError.noAPIKey {
            return false
        }
    }
}

// MARK: - Type Erasure Helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

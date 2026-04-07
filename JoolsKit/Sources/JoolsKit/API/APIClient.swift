import Foundation
import os

/// Actor-based API client for the Jules API
public actor APIClient {
    // MARK: - Properties

    private let session: URLSession
    private let keychain: KeychainManager
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "com.indrasvat.jools", category: "APIClient")
    private var supportsActivityCreateTimeFilter = true

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
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback to standard ISO8601
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }

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

        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw NetworkError.invalidResponse
        }
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

        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let diagnostic = makeDecodingDiagnostic(
                endpoint: endpoint,
                statusCode: httpResponse.statusCode,
                data: data,
                error: error
            )
            logger.error("\(diagnostic.errorDescription ?? "decode failure", privacy: .public)")
            throw NetworkError.decodingFailed(diagnostic)
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

    /// List a single page of connected sources (repositories).
    public func listSources(pageToken: String? = nil) async throws -> PaginatedResponse<SourceDTO> {
        try await request(.sources(pageToken: pageToken))
    }

    /// Walk every page of sources and return them as a flat array.
    public func listAllSources() async throws -> [SourceDTO] {
        var pageToken: String?
        var aggregated: [SourceDTO] = []
        repeat {
            let response = try await listSources(pageToken: pageToken)
            aggregated.append(contentsOf: response.allItems)
            pageToken = response.nextPageToken
        } while pageToken != nil
        return aggregated
    }

    /// Get a specific source by ID
    public func getSource(id: String) async throws -> SourceDTO {
        try await request(.source(id: id))
    }

    // MARK: - Sessions

    /// List a single page of sessions.
    public func listSessions(pageSize: Int = 20, pageToken: String? = nil) async throws -> PaginatedResponse<SessionDTO> {
        try await request(.sessions(pageSize: pageSize, pageToken: pageToken))
    }

    /// Walk every page of sessions and return them as a flat array.
    /// Required for the Sessions list and the Home dashboard sync —
    /// without this, callers silently truncate at the first page and
    /// users with more than `pageSize` sessions lose visibility of
    /// the older ones after refresh.
    public func listAllSessions(pageSize: Int = 100) async throws -> [SessionDTO] {
        var pageToken: String?
        var aggregated: [SessionDTO] = []
        repeat {
            let response = try await listSessions(pageSize: pageSize, pageToken: pageToken)
            aggregated.append(contentsOf: response.allItems)
            pageToken = response.nextPageToken
        } while pageToken != nil
        return aggregated
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
        pageToken: String? = nil,
        createTime: Date? = nil
    ) async throws -> PaginatedResponse<ActivityDTO> {
        let requestedCreateTime = supportsActivityCreateTimeFilter ? createTime : nil

        do {
            return try await request(
                .activities(
                    sessionId: sessionId,
                    pageSize: pageSize,
                    pageToken: pageToken,
                    createTime: requestedCreateTime
                )
            )
        } catch NetworkError.apiError(let message)
            where createTime != nil && requestedCreateTime != nil && isUnsupportedCreateTimeFilter(message) {
            supportsActivityCreateTimeFilter = false
            logger.notice("Activity createTime filter unsupported; falling back to full activity fetches")
            return try await request(.activities(sessionId: sessionId, pageSize: pageSize, pageToken: pageToken, createTime: nil))
        }
    }

    public func listAllActivities(
        sessionId: String,
        pageSize: Int = 100,
        createTime: Date? = nil
    ) async throws -> [ActivityDTO] {
        var pageToken: String?
        var aggregated: [ActivityDTO] = []

        repeat {
            let response = try await listActivities(
                sessionId: sessionId,
                pageSize: pageSize,
                pageToken: pageToken,
                createTime: createTime
            )
            aggregated.append(contentsOf: response.allItems)
            pageToken = response.nextPageToken
        } while pageToken != nil

        guard let createTime else { return aggregated }
        return aggregated.filter { activity in
            guard let activityCreateTime = activity.createTime else { return true }
            return activityCreateTime > createTime
        }
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

extension APIClient {
    private func makeDecodingDiagnostic(
        endpoint: Endpoint,
        statusCode: Int,
        data: Data,
        error: Error
    ) -> ResponseDecodingDiagnostic {
        let jsonObject = try? JSONSerialization.jsonObject(with: data)
        let topLevelKeys: [String]
        let activitySamples: [ResponseDecodingDiagnostic.ActivitySample]

        if let dictionary = jsonObject as? [String: Any] {
            topLevelKeys = dictionary.keys.sorted()
            if let activities = dictionary["activities"] as? [[String: Any]] {
                activitySamples = activities.prefix(3).map { activity in
                    ResponseDecodingDiagnostic.ActivitySample(
                        id: activity["id"] as? String ?? "unknown",
                        createTime: activity["createTime"] as? String
                    )
                }
            } else {
                activitySamples = []
            }
        } else {
            topLevelKeys = []
            activitySamples = []
        }

        return ResponseDecodingDiagnostic(
            endpointPath: endpoint.path,
            statusCode: statusCode,
            responseSize: data.count,
            topLevelKeys: topLevelKeys,
            activitySamples: activitySamples,
            underlyingDescription: error.localizedDescription
        )
    }

    private func isUnsupportedCreateTimeFilter(_ message: String) -> Bool {
        message.contains("Unknown name \"createTime\"") ||
        message.contains("Field 'createTime' could not be found")
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

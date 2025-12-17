import Foundation

/// HTTP methods supported by the Jules API
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// API endpoints for the Jules API
public enum Endpoint: Sendable {
    // Sources
    case sources(pageToken: String?)
    case source(id: String)

    // Sessions
    case sessions(pageSize: Int, pageToken: String?)
    case session(id: String)
    case createSession
    case deleteSession(id: String)
    case approvePlan(sessionId: String)
    case sendMessage(sessionId: String)

    // Activities
    case activities(sessionId: String, pageSize: Int, pageToken: String?)
    case activity(sessionId: String, activityId: String)

    /// The URL path for this endpoint
    public var path: String {
        switch self {
        case .sources(let pageToken):
            var path = "sources"
            if let token = pageToken {
                path += "?pageToken=\(token)"
            }
            return path

        case .source(let id):
            return "sources/\(id)"

        case .sessions(let pageSize, let pageToken):
            var path = "sessions?pageSize=\(pageSize)"
            if let token = pageToken {
                path += "&pageToken=\(token)"
            }
            return path

        case .session(let id):
            return "sessions/\(id)"

        case .createSession:
            return "sessions"

        case .deleteSession(let id):
            return "sessions/\(id)"

        case .approvePlan(let sessionId):
            return "sessions/\(sessionId):approvePlan"

        case .sendMessage(let sessionId):
            return "sessions/\(sessionId):sendMessage"

        case .activities(let sessionId, let pageSize, let pageToken):
            var path = "sessions/\(sessionId)/activities?pageSize=\(pageSize)"
            if let token = pageToken {
                path += "&pageToken=\(token)"
            }
            return path

        case .activity(let sessionId, let activityId):
            return "sessions/\(sessionId)/activities/\(activityId)"
        }
    }

    /// The HTTP method for this endpoint
    public var method: HTTPMethod {
        switch self {
        case .sources, .source, .sessions, .session, .activities, .activity:
            return .get
        case .createSession, .approvePlan, .sendMessage:
            return .post
        case .deleteSession:
            return .delete
        }
    }
}

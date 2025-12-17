import Foundation

/// Errors that can occur during network operations with the Jules API
public enum NetworkError: Error, LocalizedError, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case invalidResponse
    case apiError(String)
    case unknown(Int)
    case noAPIKey
    case encodingFailed
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid API key. Please check your credentials."
        case .forbidden:
            return "Access denied. You don't have permission for this action."
        case .notFound:
            return "Resource not found."
        case .rateLimited:
            return "You've reached your usage limit. Please try again later or upgrade your plan."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .invalidResponse:
            return "Invalid response from server."
        case .apiError(let message):
            return message
        case .unknown(let code):
            return "Unknown error (\(code))."
        case .noAPIKey:
            return "No API key configured. Please add your Jules API key."
        case .encodingFailed:
            return "Failed to encode request."
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .serverError, .unknown:
            return true
        case .rateLimited:
            return true // With backoff
        default:
            return false
        }
    }
}

/// API error response structure from Jules API
public struct APIErrorResponse: Codable, Sendable {
    public let error: APIError

    public struct APIError: Codable, Sendable {
        public let code: Int
        public let message: String
        public let status: String?
    }
}

# Jools Implementation Guide v2

**Document Type:** Comprehensive Implementation Guide
**Version:** 2.0
**Last Updated:** 2025-12-16
**Verified Against:** Official Jules API Documentation (December 2025)
**Target Platform:** iOS 26.0+ / macOS Sequoia
**Language:** Swift 6.0 (Strict Concurrency)
**IDE:** Xcode 26.1.1
**Design System:** Apple Intelligence Aesthetic

---

## Quick Navigation

1. [Executive Summary](#1-executive-summary)
2. [Jules API Reference (Verified)](#2-jules-api-reference-verified)
3. [Architecture & Design](#3-architecture--design)
4. [Data Models & Persistence](#4-data-models--persistence)
5. [Network Layer](#5-network-layer)
6. [Polling Strategy](#6-polling-strategy)
7. [UI/UX Design System](#7-uiux-design-system)
8. [Feature Specifications](#8-feature-specifications)
9. [Security & Privacy](#9-security--privacy)
10. [Implementation Phases](#10-implementation-phases)
11. [Testing Strategy](#11-testing-strategy)
12. [Package.swift (JoolsKit SPM)](#12-packageswift-joolskit-spm)
13. [Navigation Coordinator](#13-navigation-coordinator)
14. [Create Session Screen](#14-create-session-screen)
15. [Settings Screen](#15-settings-screen)
16. [Loading, Empty & Error States](#16-loading-empty--error-states)
17. [Markdown Rendering](#17-markdown-rendering)
18. [Offline Mode Specification](#18-offline-mode-specification)
19. [Project Configuration](#19-project-configuration)
20. [Accessibility Guidelines](#20-accessibility-guidelines)
21. [HTML UI Mocks](#21-html-ui-mocks)
22. [Appendices](#22-appendices)

---

## 1. Executive Summary

### Vision

**Jools** is the definitive iOS client for Google's **Jules** coding agent. It provides a "Pocket CTO" experience—allowing developers to orchestrate code tasks, review architectural plans, and manage autonomous coding sessions from anywhere.

### Key Differentiators

1. **Native iOS Excellence:** Built with SwiftUI 6, SwiftData, and full iOS 26 feature adoption
2. **Offline-First Architecture:** Full functionality in airplane mode with intelligent sync
3. **Smart Polling Engine:** Adaptive polling that respects battery while ensuring real-time feel
4. **Context Injection:** Upload local files to enrich agent context
5. **Plan Management:** First-class support for reviewing and approving Jules plans
6. **Multi-Account Ready:** Prepared for future Workspace account support

### User Journey

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           JOOLS USER JOURNEY                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │  Onboard │───▶│  Browse  │───▶│  Create  │───▶│  Review  │          │
│  │          │    │  Sources │    │  Session │    │   Plan   │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│       │               │               │               │                 │
│       ▼               ▼               ▼               ▼                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │  Enter   │    │  Select  │    │  Write   │    │ Approve/ │          │
│  │ API Key  │    │   Repo   │    │  Prompt  │    │  Reject  │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                                       │                 │
│                                                       ▼                 │
│                                              ┌──────────┐              │
│                                              │  Monitor │              │
│                                              │ Progress │              │
│                                              └──────────┘              │
│                                                       │                 │
│                                                       ▼                 │
│                                              ┌──────────┐              │
│                                              │   View   │              │
│                                              │   PR     │              │
│                                              └──────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Jules API Reference (Verified)

> **Source:** Official Jules Documentation at jules.google.com/docs (December 2025)
> **API Status:** Alpha (v1alpha) - Specifications may change

### 2.1 Base Configuration

| Property | Value |
|----------|-------|
| **Base URL** | `https://jules.googleapis.com/v1alpha/` |
| **Authentication** | API Key via `X-Goog-Api-Key` header |
| **Max API Keys** | 3 per account |
| **Content-Type** | `application/json` |
| **Transport** | HTTPS (TLS 1.3) |

### 2.2 Usage Limits (Critical for iOS UX)

| Plan | Daily Tasks | Concurrent Tasks | Model Access |
|------|-------------|------------------|--------------|
| **Free** | 15 | 3 | Gemini 2.5 Pro |
| **Pro** (Google AI Pro) | 100 | 15 | Gemini 3 Pro (higher access) |
| **Ultra** (Google AI Ultra) | 300 | 60 | Gemini 3 Pro (priority) |

**UX Implications:**
- Display remaining daily tasks in dashboard header
- Show concurrent task indicator
- Graceful handling when limits reached
- Upgrade prompt integration

### 2.3 Core Resources

#### Source
A GitHub repository connected to Jules.

```json
{
  "name": "sources/github/{owner}/{repo}",
  "id": "github/{owner}/{repo}",
  "githubRepo": {
    "owner": "string",
    "repo": "string"
  }
}
```

**Important:** Before using a source via API, you must install the Jules GitHub app through the web UI.

#### Session
A unit of work within a specific repository context.

```json
{
  "name": "sessions/{sessionId}",
  "id": "string",
  "title": "string",
  "prompt": "string",
  "state": "SESSION_STATE_ENUM",
  "sourceContext": {
    "source": "sources/github/{owner}/{repo}",
    "githubRepoContext": {
      "startingBranch": "main"
    }
  },
  "automationMode": "AUTOMATION_MODE_ENUM",
  "requirePlanApproval": boolean,
  "outputs": [
    {
      "pullRequest": {
        "url": "string",
        "title": "string",
        "description": "string"
      }
    }
  ],
  "createTime": "timestamp",
  "updateTime": "timestamp"
}
```

**Session States:**
| State | Description | iOS UX |
|-------|-------------|--------|
| `UNSPECIFIED` | Unknown | Show spinner |
| `QUEUED` | Waiting to start | Show queue position |
| `RUNNING` | Actively working | Show progress indicator |
| `AWAITING_USER_INPUT` | Needs user action | Show notification badge |
| `COMPLETED` | Successfully finished | Show success state |
| `FAILED` | Encountered error | Show error + retry option |
| `CANCELLED` | User cancelled | Show cancelled state |

**Automation Modes:**
| Mode | Description |
|------|-------------|
| `AUTOMATION_MODE_UNSPECIFIED` | Default (no auto PR) |
| `AUTO_CREATE_PR` | Automatically create PR on completion |

**Session Modes (UI Concept):**
| Mode | API Mapping | Description |
|------|-------------|-------------|
| `Interactive Plan` | `requirePlanApproval: true` + chat-first | Chat with Jules to understand goals before planning |
| `Review` | `requirePlanApproval: true` | Generate plan and wait for approval |
| `Start` | `requirePlanApproval: false` | Get started without plan approval |

> **Note:** The Jules API uses `requirePlanApproval` boolean. "Interactive Plan" mode is a UX pattern where users chat first to refine requirements before Jules generates a plan. This is achieved client-side by encouraging initial message exchange before plan generation.

#### Activity
A single action within a session (message, plan, progress update).

```json
{
  "name": "sessions/{sessionId}/activities/{activityId}",
  "id": "string",
  "type": "ACTIVITY_TYPE_ENUM",
  "createTime": "timestamp",
  "content": { /* varies by type */ }
}
```

**Activity Types:**
| Type | Description | Content Structure |
|------|-------------|-------------------|
| `PLAN_GENERATED` | Agent created a plan | `{ "plan": { "steps": [...] } }` |
| `PLAN_APPROVED` | User approved the plan | `{}` |
| `USER_MESSAGED` | User sent a message | `{ "message": "string" }` |
| `AGENT_MESSAGED` | Agent sent a message | `{ "message": "string" }` |
| `PROGRESS_UPDATED` | Status update | `{ "progress": "string" }` |
| `SESSION_COMPLETED` | Session finished | `{ "summary": "string" }` |
| `SESSION_FAILED` | Session errored | `{ "error": "string" }` |

**Artifacts (within Activities):**
- `ChangeSet`: Code changes (files modified, added, deleted)
- `BashOutput`: Command execution results
- `Media`: Images or other binary content

### 2.4 API Endpoints

#### Sources

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/sources` | List all connected sources |
| `GET` | `/sources/{sourceId}` | Get specific source details |

**List Sources Request:**
```bash
curl -H "x-goog-api-key: $API_KEY" \
  https://jules.googleapis.com/v1alpha/sources
```

**Response:**
```json
{
  "sources": [...],
  "nextPageToken": "string"
}
```

#### Sessions

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/sessions` | List sessions |
| `POST` | `/sessions` | Create new session |
| `GET` | `/sessions/{id}` | Get session details |
| `DELETE` | `/sessions/{id}` | Delete session |
| `POST` | `/sessions/{id}:approvePlan` | Approve pending plan |
| `POST` | `/sessions/{id}:sendMessage` | Send message to agent |

**Create Session Request:**
```json
{
  "prompt": "Fix the login bug",
  "sourceContext": {
    "source": "sources/github/owner/repo",
    "githubRepoContext": {
      "startingBranch": "main"
    }
  },
  "title": "Login Bug Fix",
  "automationMode": "AUTO_CREATE_PR",
  "requirePlanApproval": true
}
```

**Send Message Request:**
```json
{
  "prompt": "Can you also add unit tests?"
}
```

#### Activities

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/sessions/{id}/activities` | List activities in session |
| `GET` | `/sessions/{id}/activities/{activityId}` | Get specific activity |

**Query Parameters:**
- `pageSize`: Number of results (default: 30)
- `pageToken`: Pagination token

### 2.5 Error Handling

**HTTP Status Codes:**
| Code | Meaning | iOS Handling |
|------|---------|--------------|
| `200` | Success | Process response |
| `400` | Bad Request | Show validation error |
| `401` | Unauthorized | Redirect to login |
| `403` | Forbidden | Show access denied |
| `404` | Not Found | Show not found state |
| `429` | Rate Limited | Show limit reached + retry |
| `500` | Server Error | Show error + retry option |

**Error Response Format:**
```json
{
  "error": {
    "code": 400,
    "message": "Invalid request",
    "status": "INVALID_ARGUMENT",
    "details": [...]
  }
}
```

---

## 3. Architecture & Design

### 3.1 Module Structure

```
Jools/
├── JoolsKit/                    # Core framework (SPM)
│   ├── Sources/
│   │   ├── API/
│   │   │   ├── APIClient.swift
│   │   │   ├── Endpoints.swift
│   │   │   └── NetworkError.swift
│   │   ├── Models/
│   │   │   ├── Source.swift
│   │   │   ├── Session.swift
│   │   │   ├── Activity.swift
│   │   │   └── DTOs.swift
│   │   ├── Auth/
│   │   │   └── KeychainManager.swift
│   │   └── Polling/
│   │       └── PollingService.swift
│   └── Tests/
│
├── Jools/                       # iOS App
│   ├── App/
│   │   ├── JoolsApp.swift
│   │   └── AppDependency.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   ├── Dashboard/
│   │   ├── Chat/
│   │   ├── Plan/
│   │   └── Settings/
│   ├── Core/
│   │   ├── DesignSystem/
│   │   ├── Navigation/
│   │   └── Persistence/
│   └── Resources/
│
└── JoolsTests/
```

### 3.2 MVVM+C Pattern

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           MVVM+C ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                         COORDINATOR                               │  │
│  │  • Manages NavigationPath                                        │  │
│  │  • Handles deep links                                            │  │
│  │  • Controls flow between features                                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                          VIEW                                     │  │
│  │  • Pure SwiftUI                                                  │  │
│  │  • Observes ViewModel                                            │  │
│  │  • Sends user actions                                            │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                        VIEWMODEL                                  │  │
│  │  • @Observable class                                             │  │
│  │  • @MainActor for UI state                                       │  │
│  │  • Business logic                                                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                         MODEL                                     │  │
│  │  • SwiftData entities                                            │  │
│  │  • API DTOs (Codable)                                            │  │
│  │  • Domain objects                                                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Dependency Injection

```swift
// AppDependency.swift
@MainActor
final class AppDependency: ObservableObject {
    let apiClient: APIClient
    let keychainManager: KeychainManager
    let pollingService: PollingService
    let modelContainer: ModelContainer

    init() {
        self.keychainManager = KeychainManager()
        self.apiClient = APIClient(keychain: keychainManager)
        self.modelContainer = try! ModelContainer(for: SessionEntity.self, SourceEntity.self)
        self.pollingService = PollingService(api: apiClient, modelContainer: modelContainer)
    }
}

// JoolsApp.swift
@main
struct JoolsApp: App {
    @StateObject private var dependencies = AppDependency()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
```

---

## 4. Data Models & Persistence

### 4.1 SwiftData Schema

```swift
import SwiftData

// MARK: - Source Entity
@Model
final class SourceEntity {
    @Attribute(.unique) var id: String
    var name: String
    var owner: String
    var repo: String
    var lastSyncedAt: Date?

    init(from dto: SourceDTO) {
        self.id = dto.id
        self.name = dto.name
        self.owner = dto.githubRepo.owner
        self.repo = dto.githubRepo.repo
        self.lastSyncedAt = Date()
    }
}

// MARK: - Session Entity
@Model
final class SessionEntity {
    @Attribute(.unique) var id: String
    var title: String
    var prompt: String
    var state: SessionState
    var sourceId: String
    var sourceBranch: String
    var automationMode: AutomationMode
    var requirePlanApproval: Bool
    var createdAt: Date
    var updatedAt: Date
    var prURL: String?
    var prTitle: String?
    var prDescription: String?

    @Relationship(deleteRule: .cascade, inverse: \ActivityEntity.session)
    var activities: [ActivityEntity] = []

    init(from dto: SessionDTO) {
        self.id = dto.id
        self.title = dto.title ?? "Untitled"
        self.prompt = dto.prompt
        self.state = SessionState(rawValue: dto.state) ?? .unspecified
        self.sourceId = dto.sourceContext.source
        self.sourceBranch = dto.sourceContext.githubRepoContext?.startingBranch ?? "main"
        self.automationMode = AutomationMode(rawValue: dto.automationMode ?? "") ?? .unspecified
        self.requirePlanApproval = dto.requirePlanApproval ?? false
        self.createdAt = dto.createTime ?? Date()
        self.updatedAt = dto.updateTime ?? Date()
        if let output = dto.outputs?.first?.pullRequest {
            self.prURL = output.url
            self.prTitle = output.title
            self.prDescription = output.description
        }
    }
}

// MARK: - Activity Entity
@Model
final class ActivityEntity {
    @Attribute(.unique) var id: String
    var type: ActivityType
    var createdAt: Date
    var contentJSON: Data  // Flexible storage for varying content
    var isOptimistic: Bool = false  // For optimistic UI updates
    var sendStatus: SendStatus = .sent

    var session: SessionEntity?

    init(from dto: ActivityDTO) {
        self.id = dto.id
        self.type = ActivityType(rawValue: dto.type) ?? .unknown
        self.createdAt = dto.createTime ?? Date()
        self.contentJSON = try! JSONEncoder().encode(dto.content)
        self.isOptimistic = false
        self.sendStatus = .sent
    }

    // For optimistic messages
    init(optimisticMessage: String, sessionId: String) {
        self.id = UUID().uuidString
        self.type = .userMessaged
        self.createdAt = Date()
        self.contentJSON = try! JSONEncoder().encode(["message": optimisticMessage])
        self.isOptimistic = true
        self.sendStatus = .pending
    }
}

// MARK: - Enums
enum SessionState: String, Codable {
    case unspecified = "SESSION_STATE_UNSPECIFIED"
    case queued = "QUEUED"
    case running = "RUNNING"
    case awaitingUserInput = "AWAITING_USER_INPUT"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

enum AutomationMode: String, Codable {
    case unspecified = "AUTOMATION_MODE_UNSPECIFIED"
    case autoCreatePR = "AUTO_CREATE_PR"
}

enum ActivityType: String, Codable {
    case unknown = "UNKNOWN"
    case planGenerated = "PLAN_GENERATED"
    case planApproved = "PLAN_APPROVED"
    case userMessaged = "USER_MESSAGED"
    case agentMessaged = "AGENT_MESSAGED"
    case progressUpdated = "PROGRESS_UPDATED"
    case sessionCompleted = "SESSION_COMPLETED"
    case sessionFailed = "SESSION_FAILED"
}

enum SendStatus: String, Codable {
    case pending
    case sent
    case failed
}
```

### 4.2 DTO Structures

```swift
// MARK: - API Response DTOs
struct SourceDTO: Codable {
    let name: String
    let id: String
    let githubRepo: GitHubRepoDTO
}

struct GitHubRepoDTO: Codable {
    let owner: String
    let repo: String
}

struct SessionDTO: Codable {
    let name: String
    let id: String
    let title: String?
    let prompt: String
    let state: String?
    let sourceContext: SourceContextDTO
    let automationMode: String?
    let requirePlanApproval: Bool?
    let outputs: [SessionOutputDTO]?
    let createTime: Date?
    let updateTime: Date?
}

struct SourceContextDTO: Codable {
    let source: String
    let githubRepoContext: GitHubRepoContextDTO?
}

struct GitHubRepoContextDTO: Codable {
    let startingBranch: String?
}

struct SessionOutputDTO: Codable {
    let pullRequest: PullRequestDTO?
}

struct PullRequestDTO: Codable {
    let url: String
    let title: String
    let description: String?
}

struct ActivityDTO: Codable {
    let name: String
    let id: String
    let type: String
    let createTime: Date?
    let content: [String: AnyCodable]?
}

// MARK: - Request DTOs
struct CreateSessionRequest: Codable {
    let prompt: String
    let sourceContext: SourceContextDTO
    let title: String?
    let automationMode: String?
    let requirePlanApproval: Bool?
}

struct SendMessageRequest: Codable {
    let prompt: String
}

// MARK: - Paginated Response
struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]?
    let sessions: [T]?
    let sources: [T]?
    let activities: [T]?
    let nextPageToken: String?

    var allItems: [T] {
        items ?? sessions ?? sources ?? activities ?? []
    }
}
```

---

## 5. Network Layer

### 5.1 API Client

```swift
import Foundation

actor APIClient {
    private let session: URLSession
    private let keychain: KeychainManager
    private let baseURL = URL(string: "https://jules.googleapis.com/v1alpha/")!
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(keychain: KeychainManager, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Generic Request
    private func request<T: Decodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws -> T {
        guard let apiKey = keychain.loadAPIKey() else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = method.rawValue
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        return try decoder.decode(T.self, from: data)
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
    func listSources(pageToken: String? = nil) async throws -> PaginatedResponse<SourceDTO> {
        try await request(.sources(pageToken: pageToken))
    }

    // MARK: - Sessions
    func listSessions(pageSize: Int = 20, pageToken: String? = nil) async throws -> PaginatedResponse<SessionDTO> {
        try await request(.sessions(pageSize: pageSize, pageToken: pageToken))
    }

    func getSession(id: String) async throws -> SessionDTO {
        try await request(.session(id: id))
    }

    func createSession(_ request: CreateSessionRequest) async throws -> SessionDTO {
        try await self.request(.createSession, method: .post, body: request)
    }

    func deleteSession(id: String) async throws {
        let _: EmptyResponse = try await request(.session(id: id), method: .delete)
    }

    func approvePlan(sessionId: String) async throws {
        let _: EmptyResponse = try await request(.approvePlan(sessionId: sessionId), method: .post)
    }

    func sendMessage(sessionId: String, message: String) async throws {
        let body = SendMessageRequest(prompt: message)
        let _: EmptyResponse = try await request(.sendMessage(sessionId: sessionId), method: .post, body: body)
    }

    // MARK: - Activities
    func listActivities(sessionId: String, pageSize: Int = 30, pageToken: String? = nil) async throws -> PaginatedResponse<ActivityDTO> {
        try await request(.activities(sessionId: sessionId, pageSize: pageSize, pageToken: pageToken))
    }

    // MARK: - Validation
    func validateAPIKey() async throws -> Bool {
        do {
            let _: PaginatedResponse<SourceDTO> = try await request(.sources(pageToken: nil))
            return true
        } catch NetworkError.unauthorized {
            return false
        }
    }
}

// MARK: - Supporting Types
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case patch = "PATCH"
}

enum Endpoint {
    case sources(pageToken: String?)
    case source(id: String)
    case sessions(pageSize: Int, pageToken: String?)
    case session(id: String)
    case createSession
    case approvePlan(sessionId: String)
    case sendMessage(sessionId: String)
    case activities(sessionId: String, pageSize: Int, pageToken: String?)
    case activity(sessionId: String, activityId: String)

    var path: String {
        switch self {
        case .sources(let pageToken):
            var path = "sources"
            if let token = pageToken { path += "?pageToken=\(token)" }
            return path
        case .source(let id):
            return "sources/\(id)"
        case .sessions(let pageSize, let pageToken):
            var path = "sessions?pageSize=\(pageSize)"
            if let token = pageToken { path += "&pageToken=\(token)" }
            return path
        case .session(let id):
            return "sessions/\(id)"
        case .createSession:
            return "sessions"
        case .approvePlan(let sessionId):
            return "sessions/\(sessionId):approvePlan"
        case .sendMessage(let sessionId):
            return "sessions/\(sessionId):sendMessage"
        case .activities(let sessionId, let pageSize, let pageToken):
            var path = "sessions/\(sessionId)/activities?pageSize=\(pageSize)"
            if let token = pageToken { path += "&pageToken=\(token)" }
            return path
        case .activity(let sessionId, let activityId):
            return "sessions/\(sessionId)/activities/\(activityId)"
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case invalidResponse
    case apiError(String)
    case unknown(Int)

    var errorDescription: String? {
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
        }
    }
}

struct APIErrorResponse: Codable {
    let error: APIError

    struct APIError: Codable {
        let code: Int
        let message: String
        let status: String?
    }
}

struct EmptyResponse: Codable {}
```

---

## 6. Polling Strategy

### 6.1 Adaptive Polling Engine

```swift
import Foundation
import Combine

@MainActor
final class PollingService: ObservableObject {
    // MARK: - Configuration
    private enum Config {
        static let activeInterval: TimeInterval = 3.0
        static let idleInterval: TimeInterval = 10.0
        static let backgroundInterval: TimeInterval = 60.0
        static let idleThreshold: TimeInterval = 30.0
    }

    // MARK: - State
    enum PollingState {
        case active
        case idle
        case background
        case stopped
    }

    @Published private(set) var state: PollingState = .stopped
    @Published private(set) var isPolling: Bool = false

    private let api: APIClient
    private let modelContainer: ModelContainer
    private var pollingTask: Task<Void, Never>?
    private var lastUserInteraction: Date = Date()
    private var activeSessionId: String?

    init(api: APIClient, modelContainer: ModelContainer) {
        self.api = api
        self.modelContainer = modelContainer
        setupNotifications()
    }

    // MARK: - Public API
    func startPolling(sessionId: String) {
        activeSessionId = sessionId
        state = .active
        lastUserInteraction = Date()
        restartPollingLoop()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .stopped
        isPolling = false
        activeSessionId = nil
    }

    func userDidInteract() {
        lastUserInteraction = Date()
        if state == .idle {
            state = .active
            restartPollingLoop()
        }
    }

    func triggerImmediatePoll() {
        guard let sessionId = activeSessionId else { return }
        Task {
            await performPoll(sessionId: sessionId)
        }
    }

    // MARK: - Private
    private func restartPollingLoop() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, let sessionId = self.activeSessionId else { break }

                self.isPolling = true
                await self.performPoll(sessionId: sessionId)
                self.isPolling = false

                self.updateStateIfNeeded()

                let interval = self.currentInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func performPoll(sessionId: String) async {
        do {
            // Fetch session updates
            let session = try await api.getSession(id: sessionId)
            await updateSession(session)

            // Fetch new activities
            let activities = try await api.listActivities(sessionId: sessionId, pageSize: 30)
            await updateActivities(activities.allItems, sessionId: sessionId)

        } catch {
            // Log but don't stop polling
            print("Poll failed: \(error.localizedDescription)")
        }
    }

    @ModelActor
    private func updateSession(_ dto: SessionDTO) {
        // Update SwiftData
    }

    @ModelActor
    private func updateActivities(_ dtos: [ActivityDTO], sessionId: String) {
        // Update SwiftData
    }

    private func updateStateIfNeeded() {
        let timeSinceInteraction = Date().timeIntervalSince(lastUserInteraction)
        if timeSinceInteraction > Config.idleThreshold && state == .active {
            state = .idle
        }
    }

    private var currentInterval: TimeInterval {
        switch state {
        case .active:
            return Config.activeInterval
        case .idle:
            return Config.idleInterval
        case .background:
            return Config.backgroundInterval
        case .stopped:
            return .infinity
        }
    }

    // MARK: - App Lifecycle
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.state = .background
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.state = .active
            self?.lastUserInteraction = Date()
            self?.restartPollingLoop()
        }
    }
}
```

### 6.2 Background Refresh

```swift
import BackgroundTasks

extension AppDelegate {
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.jools.refresh",
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.jools.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        try? BGTaskScheduler.shared.submit(request)
    }

    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh() // Schedule next refresh

        let refreshTask = Task {
            // Fetch updates for active sessions
            // Update SwiftData
            // Send local notification if attention needed
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            await refreshTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
```

---

## 7. UI/UX Design System

### 7.1 Design Tokens

```swift
import SwiftUI

// MARK: - Colors
extension Color {
    static let joolsAccent = Color("AccentColor")
    static let joolsBackground = Color(uiColor: .systemBackground)
    static let joolsSurface = Color(uiColor: .secondarySystemBackground)
    static let joolsBubbleUser = Color.blue
    static let joolsBubbleAgent = Color(uiColor: .tertiarySystemBackground)
    static let joolsPlanBorder = Color.orange
    static let joolsSuccess = Color.green
    static let joolsError = Color.red
    static let joolsWarning = Color.yellow
}

// MARK: - Typography
extension Font {
    static let joolsLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let joolsTitle = Font.system(.title, design: .rounded).weight(.semibold)
    static let joolsHeadline = Font.system(.headline, design: .default)
    static let joolsBody = Font.system(.body, design: .default)
    static let joolsCaption = Font.system(.caption, design: .default)
    static let joolsCode = Font.system(.body, design: .monospaced)
}

// MARK: - Spacing
enum JoolsSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius
enum JoolsRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}
```

### 7.2 Component Library

```swift
// MARK: - Message Bubble
struct MessageBubble: View {
    let activity: ActivityEntity

    var body: some View {
        HStack {
            if activity.type == .userMessaged {
                Spacer(minLength: 60)
            }

            VStack(alignment: activity.type == .userMessaged ? .trailing : .leading, spacing: 4) {
                Text(messageContent)
                    .font(.joolsBody)
                    .padding(.horizontal, JoolsSpacing.md)
                    .padding(.vertical, JoolsSpacing.sm)
                    .background(bubbleColor)
                    .foregroundColor(textColor)
                    .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

                HStack(spacing: JoolsSpacing.xxs) {
                    Text(activity.createdAt, style: .time)
                        .font(.joolsCaption)
                        .foregroundColor(.secondary)

                    if activity.type == .userMessaged {
                        statusIcon
                    }
                }
            }

            if activity.type != .userMessaged {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, JoolsSpacing.md)
    }

    private var messageContent: String {
        // Decode from contentJSON
        guard let data = activity.contentJSON,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let message = dict["message"] else {
            return ""
        }
        return message
    }

    private var bubbleColor: Color {
        activity.type == .userMessaged ? .joolsBubbleUser : .joolsBubbleAgent
    }

    private var textColor: Color {
        activity.type == .userMessaged ? .white : .primary
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch activity.sendStatus {
        case .pending:
            ProgressView()
                .scaleEffect(0.6)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.joolsError)
        }
    }
}

// MARK: - Plan Card
struct PlanCard: View {
    let activity: ActivityEntity
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.joolsPlanBorder)
                Text("Proposed Plan")
                    .font(.joolsHeadline)
                Spacer()
            }

            Divider()

            // Plan steps
            VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
                ForEach(planSteps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: JoolsSpacing.xs) {
                        Text("\(index + 1).")
                            .font(.joolsCaption)
                            .foregroundColor(.secondary)
                        Text(planSteps[index])
                            .font(.joolsBody)
                    }
                }
            }

            Divider()

            HStack(spacing: JoolsSpacing.md) {
                Button(action: onReject) {
                    Label("Reject", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(JoolsSpacing.md)
        .background(Color.joolsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: JoolsRadius.md)
                .stroke(Color.joolsPlanBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
        .padding(.horizontal, JoolsSpacing.md)
    }

    private var planSteps: [String] {
        // Decode from contentJSON
        []
    }
}

// MARK: - Session State Badge
struct SessionStateBadge: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: JoolsSpacing.xxs) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateText)
                .font(.joolsCaption)
                .foregroundColor(.secondary)
        }
    }

    private var stateColor: Color {
        switch state {
        case .running:
            return .joolsSuccess
        case .awaitingUserInput:
            return .joolsWarning
        case .completed:
            return .joolsAccent
        case .failed:
            return .joolsError
        default:
            return .secondary
        }
    }

    private var stateText: String {
        switch state {
        case .unspecified:
            return "Unknown"
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .awaitingUserInput:
            return "Needs Input"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}
```

### 7.3 Animations & Haptics

```swift
// MARK: - Animation Extensions
extension Animation {
    static let joolsSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let joolsFast = Animation.easeOut(duration: 0.2)
    static let joolsSlow = Animation.easeInOut(duration: 0.5)
}

// MARK: - Haptic Manager
final class HapticManager {
    static let shared = HapticManager()

    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    func selection() {
        selectionGenerator.selectionChanged()
    }

    func impact() {
        impactGenerator.impactOccurred()
    }
}

// MARK: - View Modifiers
extension View {
    func onTapWithHaptic(_ action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticManager.shared.selection()
            action()
        }
    }
}
```

---

## 8. Feature Specifications

### 8.1 Onboarding Flow

```swift
// OnboardingView.swift
struct OnboardingView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientMesh()
                .ignoresSafeArea()

            VStack(spacing: JoolsSpacing.xl) {
                Spacer()

                // Logo
                Text("JOOLS")
                    .font(.joolsLargeTitle)
                    .foregroundStyle(.white)

                Text("Your Pocket CTO")
                    .font(.joolsTitle)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // API Key Input
                VStack(spacing: JoolsSpacing.md) {
                    SecureField("Enter API Key", text: $viewModel.apiKey)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))

                    Button(action: viewModel.connect) {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKey.isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal, JoolsSpacing.lg)

                // Help link
                Link("Get your API key", destination: URL(string: "https://jules.google.com/settings")!)
                    .font(.joolsCaption)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
```

### 8.2 Dashboard

```swift
// DashboardView.swift
struct DashboardView: View {
    @EnvironmentObject private var dependencies: AppDependency
    @StateObject private var viewModel: DashboardViewModel
    @Query private var sessions: [SessionEntity]
    @Query private var sources: [SourceEntity]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: JoolsSpacing.lg) {
                    // Usage Stats
                    UsageStatsCard(viewModel: viewModel)

                    // Sources Section
                    SourcesSection(sources: sources)

                    // Recent Sessions
                    SessionsSection(sessions: sessions)
                }
                .padding()
            }
            .navigationTitle("Jools")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { /* Settings */ }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await viewModel.refreshAsync()
            }
        }
    }
}

// UsageStatsCard.swift
struct UsageStatsCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                Text("Today's Usage")
                    .font(.joolsHeadline)
                Spacer()
                Text("\(viewModel.tasksUsed)/\(viewModel.tasksLimit)")
                    .font(.joolsBody)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: Double(viewModel.tasksUsed), total: Double(viewModel.tasksLimit))
                .tint(viewModel.isNearLimit ? .joolsWarning : .joolsAccent)

            if viewModel.isNearLimit {
                Text("You're approaching your daily limit")
                    .font(.joolsCaption)
                    .foregroundColor(.joolsWarning)
            }
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}
```

### 8.3 Chat View

```swift
// ChatView.swift
struct ChatView: View {
    let session: SessionEntity
    @EnvironmentObject private var dependencies: AppDependency
    @StateObject private var viewModel: ChatViewModel
    @Query private var activities: [ActivityEntity]

    init(session: SessionEntity) {
        self.session = session
        _activities = Query(
            filter: #Predicate<ActivityEntity> { $0.session?.id == session.id },
            sort: \.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeader(session: session)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: JoolsSpacing.md) {
                        ForEach(activities) { activity in
                            ActivityView(activity: activity, viewModel: viewModel)
                                .id(activity.id)
                        }
                    }
                    .padding(.vertical)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: activities.count) { _, _ in
                    if let last = activities.first {
                        withAnimation {
                            proxy.scrollTo(last.id)
                        }
                    }
                }
            }

            Divider()

            // Input
            ChatInputBar(viewModel: viewModel)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dependencies.pollingService.startPolling(sessionId: session.id)
        }
        .onDisappear {
            dependencies.pollingService.stopPolling()
        }
    }
}

// ActivityView.swift
struct ActivityView: View {
    let activity: ActivityEntity
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        switch activity.type {
        case .userMessaged, .agentMessaged:
            MessageBubble(activity: activity)
                .transition(.scale.combined(with: .opacity))

        case .planGenerated:
            PlanCard(
                activity: activity,
                onApprove: { viewModel.approvePlan(activity: activity) },
                onReject: { viewModel.rejectPlan(activity: activity) }
            )

        case .progressUpdated:
            ProgressUpdateView(activity: activity)

        case .sessionCompleted:
            SessionCompletedView(activity: activity)

        case .sessionFailed:
            SessionFailedView(activity: activity)

        default:
            EmptyView()
        }
    }
}

// ChatInputBar.swift
struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: JoolsSpacing.sm) {
            // Attach button
            Button(action: viewModel.attachFile) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.joolsAccent)
            }

            // Text input
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, JoolsSpacing.sm)
                .padding(.vertical, JoolsSpacing.xs)
                .background(Color.joolsSurface)
                .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))

            // Send button
            Button(action: viewModel.sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(viewModel.canSend ? .joolsAccent : .secondary)
            }
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, JoolsSpacing.sm)
        .background(.bar)
    }
}
```

---

## 9. Security & Privacy

### 9.1 Keychain Management

```swift
import Security

final class KeychainManager {
    private let service = "com.jools.app"
    private let apiKeyAccount = "api-key"

    func saveAPIKey(_ key: String) throws {
        let data = key.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
```

### 9.2 Privacy Considerations

```swift
// Never log API keys
import os.log

extension Logger {
    static let network = Logger(subsystem: "com.jools", category: "network")
    static let auth = Logger(subsystem: "com.jools", category: "auth")

    func logRequest(_ request: URLRequest) {
        // Log URL but redact headers
        Logger.network.info("Request: \(request.url?.absoluteString ?? "unknown", privacy: .public)")
        // Never: Logger.network.info("Headers: \(request.allHTTPHeaderFields)")
    }
}
```

---

## 10. Implementation Phases

### Phase 0: Project Setup (Day 1)

- [ ] Create Xcode project with iOS 26 target
- [ ] Configure Swift 6 strict concurrency
- [ ] Set up JoolsKit SPM package
- [ ] Configure .gitignore
- [ ] Create Makefile with test/lint/build
- [ ] Set up SwiftLint configuration

### Phase 1: Core Infrastructure (Day 1-2)

- [ ] Implement KeychainManager
- [ ] Implement APIClient (actor-based)
- [ ] Define all DTOs with Codable
- [ ] Write unit tests for JSON decoding
- [ ] Set up SwiftData ModelContainer
- [ ] Define all entity models

### Phase 2: Authentication & Onboarding (Day 2-3)

- [ ] Create OnboardingView with glassmorphic design
- [ ] Implement OnboardingViewModel
- [ ] API key validation flow
- [ ] Keychain save/load flow
- [ ] Root navigation coordinator
- [ ] Error handling & toasts

### Phase 3: Dashboard (Day 3-4)

- [ ] DashboardView with sources grid
- [ ] Session list with state badges
- [ ] Usage stats card
- [ ] Pull-to-refresh
- [ ] Skeleton loading states
- [ ] Empty states

### Phase 4: Chat & Polling (Day 4-5)

- [ ] ChatView with inverted scroll
- [ ] Message bubbles (user/agent)
- [ ] PollingService implementation
- [ ] Optimistic message sending
- [ ] Typing indicator
- [ ] Message status indicators

### Phase 5: Plan Management (Day 5-6)

- [ ] PlanCard component
- [ ] Plan approval flow
- [ ] Plan rejection flow
- [ ] Session state transitions
- [ ] Progress updates rendering
- [ ] Session completion view

### Phase 6: Context Injection (Day 6)

- [ ] Document picker integration
- [ ] File content reading
- [ ] Token estimation
- [ ] Context preview
- [ ] Upload to session

### Phase 7: Polish & Testing (Day 7)

- [ ] Haptic feedback audit
- [ ] Animation polish
- [ ] Accessibility audit
- [ ] VoiceOver testing
- [ ] UI tests
- [ ] Performance profiling

### Phase 8: Release Prep (Day 8)

- [ ] App icons
- [ ] Launch screen
- [ ] App Store screenshots
- [ ] Privacy policy
- [ ] Release notes

---

## 11. Testing Strategy

### 11.1 Unit Tests

```swift
// APIClientTests.swift
@Suite("APIClient Tests")
struct APIClientTests {
    @Test("Decodes source list correctly")
    func testDecodeSourceList() async throws {
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

        let response = try JSONDecoder().decode(
            PaginatedResponse<SourceDTO>.self,
            from: json.data(using: .utf8)!
        )

        #expect(response.allItems.count == 1)
        #expect(response.allItems[0].id == "github/owner/repo")
    }

    @Test("Handles 401 unauthorized")
    func testUnauthorized() async {
        let mockSession = MockURLSession(statusCode: 401)
        let client = APIClient(keychain: MockKeychain(), session: mockSession)

        await #expect(throws: NetworkError.unauthorized) {
            try await client.listSources()
        }
    }
}
```

### 11.2 UI Tests

```swift
// OnboardingUITests.swift
@Suite("Onboarding UI Tests")
struct OnboardingUITests {
    @Test("Shows error for invalid API key")
    @MainActor
    func testInvalidAPIKey() async {
        let app = XCUIApplication()
        app.launch()

        let apiKeyField = app.secureTextFields["Enter API Key"]
        apiKeyField.tap()
        apiKeyField.typeText("invalid-key")

        app.buttons["Connect"].tap()

        #expect(app.alerts["Error"].exists)
    }
}
```

---

## 12. Package.swift (JoolsKit SPM)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoolsKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "JoolsKit",
            targets: ["JoolsKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "JoolsKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "JoolsKitTests",
            dependencies: ["JoolsKit"],
            path: "Tests"
        ),
    ]
)
```

---

## 13. Navigation Coordinator

### 13.1 Route Definition

```swift
// Navigation/Route.swift
import Foundation

enum Route: Hashable {
    // Auth
    case onboarding

    // Main
    case dashboard
    case sourceDetail(sourceId: String)
    case createSession(sourceId: String)
    case sessionDetail(sessionId: String)
    case chat(sessionId: String)
    case planReview(sessionId: String, activityId: String)

    // Settings
    case settings
    case settingsAccount
    case settingsAppearance
    case settingsNotifications
    case settingsAbout

    // Utility
    case webView(url: URL, title: String)
}
```

### 13.2 Coordinator Implementation

```swift
// Navigation/AppCoordinator.swift
import SwiftUI
import Observation

@Observable
@MainActor
final class AppCoordinator {
    var navigationPath = NavigationPath()
    var presentedSheet: Route?
    var presentedFullScreen: Route?
    var isAuthenticated: Bool = false

    private let keychainManager: KeychainManager

    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        self.isAuthenticated = keychainManager.loadAPIKey() != nil
    }

    // MARK: - Navigation
    func push(_ route: Route) {
        navigationPath.append(route)
    }

    func pop() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    func popToRoot() {
        navigationPath = NavigationPath()
    }

    func present(_ route: Route, fullScreen: Bool = false) {
        if fullScreen {
            presentedFullScreen = route
        } else {
            presentedSheet = route
        }
    }

    func dismiss() {
        presentedSheet = nil
        presentedFullScreen = nil
    }

    // MARK: - Auth Flow
    func onAuthSuccess() {
        isAuthenticated = true
        popToRoot()
    }

    func onLogout() {
        try? keychainManager.deleteAPIKey()
        isAuthenticated = false
        popToRoot()
    }

    // MARK: - Deep Links
    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "jools" else { return }

        switch components.host {
        case "session":
            if let sessionId = components.queryItems?.first(where: { $0.name == "id" })?.value {
                push(.sessionDetail(sessionId: sessionId))
            }
        case "settings":
            push(.settings)
        default:
            break
        }
    }
}

// MARK: - View Builder
extension AppCoordinator {
    @ViewBuilder
    func view(for route: Route) -> some View {
        switch route {
        case .onboarding:
            OnboardingView()
        case .dashboard:
            DashboardView()
        case .sourceDetail(let sourceId):
            SourceDetailView(sourceId: sourceId)
        case .createSession(let sourceId):
            CreateSessionView(sourceId: sourceId)
        case .sessionDetail(let sessionId):
            SessionDetailView(sessionId: sessionId)
        case .chat(let sessionId):
            ChatView(sessionId: sessionId)
        case .planReview(let sessionId, let activityId):
            PlanReviewView(sessionId: sessionId, activityId: activityId)
        case .settings:
            SettingsView()
        case .settingsAccount:
            AccountSettingsView()
        case .settingsAppearance:
            AppearanceSettingsView()
        case .settingsNotifications:
            NotificationSettingsView()
        case .settingsAbout:
            AboutView()
        case .webView(let url, let title):
            SafariView(url: url)
                .navigationTitle(title)
        }
    }
}
```

### 13.3 Root View

```swift
// App/RootView.swift
import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Group {
            if coordinator.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .sheet(item: sheetBinding) { route in
            NavigationStack {
                coordinator.view(for: route)
            }
        }
        .fullScreenCover(item: fullScreenBinding) { route in
            coordinator.view(for: route)
        }
        .onOpenURL { url in
            coordinator.handle(url: url)
        }
    }

    private var sheetBinding: Binding<Route?> {
        Binding(
            get: { coordinator.presentedSheet },
            set: { coordinator.presentedSheet = $0 }
        )
    }

    private var fullScreenBinding: Binding<Route?> {
        Binding(
            get: { coordinator.presentedFullScreen },
            set: { coordinator.presentedFullScreen = $0 }
        )
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $coordinator.navigationPath) {
                DashboardView()
                    .navigationDestination(for: Route.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            .tag(0)

            NavigationStack {
                SessionListView()
                    .navigationDestination(for: Route.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Sessions", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
                    .navigationDestination(for: Route.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}
```

---

## 14. Create Session Screen

### 14.1 ViewModel

```swift
// Features/CreateSession/CreateSessionViewModel.swift
import SwiftUI
import SwiftData

@Observable
@MainActor
final class CreateSessionViewModel {
    // MARK: - State
    var prompt: String = ""
    var title: String = ""
    var selectedBranch: String = "main"
    var availableBranches: [String] = ["main"]
    var autoCreatePR: Bool = true
    var requirePlanApproval: Bool = true

    var isLoading: Bool = false
    var isFetchingBranches: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - Computed
    var canCreate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var effectiveTitle: String {
        title.isEmpty ? String(prompt.prefix(50)) : title
    }

    // MARK: - Dependencies
    private let sourceId: String
    private let apiClient: APIClient
    private let coordinator: AppCoordinator

    init(sourceId: String, apiClient: APIClient, coordinator: AppCoordinator) {
        self.sourceId = sourceId
        self.apiClient = apiClient
        self.coordinator = coordinator
    }

    // MARK: - Actions
    func onAppear() async {
        await fetchBranches()
    }

    func fetchBranches() async {
        isFetchingBranches = true
        defer { isFetchingBranches = false }

        // Note: Jules API doesn't provide branches - this would need GitHub API
        // For now, default to common branches
        availableBranches = ["main", "master", "develop"]
    }

    func createSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let request = CreateSessionRequest(
                prompt: prompt,
                sourceContext: SourceContextDTO(
                    source: sourceId,
                    githubRepoContext: GitHubRepoContextDTO(startingBranch: selectedBranch)
                ),
                title: effectiveTitle,
                automationMode: autoCreatePR ? "AUTO_CREATE_PR" : nil,
                requirePlanApproval: requirePlanApproval
            )

            let session = try await apiClient.createSession(request)

            HapticManager.shared.success()
            coordinator.pop()
            coordinator.push(.chat(sessionId: session.id))

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.error()
        }
    }
}
```

### 14.2 View

```swift
// Features/CreateSession/CreateSessionView.swift
import SwiftUI

struct CreateSessionView: View {
    let sourceId: String
    @State private var viewModel: CreateSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(sourceId: String) {
        self.sourceId = sourceId
        _viewModel = State(initialValue: CreateSessionViewModel(
            sourceId: sourceId,
            apiClient: AppDependency.shared.apiClient,
            coordinator: AppDependency.shared.coordinator
        ))
    }

    var body: some View {
        Form {
            // Prompt Section
            Section {
                TextField("What should Jules work on?", text: $viewModel.prompt, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Text("Task Description")
            } footer: {
                Text("Be specific about what you want Jules to accomplish.")
            }

            // Title Section
            Section {
                TextField("Optional title", text: $viewModel.title)
            } header: {
                Text("Session Title")
            } footer: {
                Text("Leave blank to auto-generate from prompt.")
            }

            // Branch Section
            Section {
                Picker("Starting Branch", selection: $viewModel.selectedBranch) {
                    ForEach(viewModel.availableBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .disabled(viewModel.isFetchingBranches)
            } header: {
                Text("Repository")
            }

            // Options Section
            Section {
                Toggle("Auto-create Pull Request", isOn: $viewModel.autoCreatePR)
                Toggle("Require Plan Approval", isOn: $viewModel.requirePlanApproval)
            } header: {
                Text("Options")
            } footer: {
                Text("Plan approval lets you review Jules' approach before execution.")
            }
        }
        .navigationTitle("New Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    Task { await viewModel.createSession() }
                }
                .disabled(!viewModel.canCreate)
            }
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay(message: "Creating session...")
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .task {
            await viewModel.onAppear()
        }
    }
}
```

---

## 15. Settings Screen

### 15.1 ViewModel

```swift
// Features/Settings/SettingsViewModel.swift
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - State
    var apiKeyMasked: String = ""
    var planTier: String = "Pro"
    var dailyTasksUsed: Int = 0
    var dailyTasksLimit: Int = 100
    var isLoading: Bool = false
    var showLogoutConfirmation: Bool = false
    var showDeleteDataConfirmation: Bool = false

    // MARK: - App Info
    let appVersion: String
    let buildNumber: String

    // MARK: - Dependencies
    private let keychainManager: KeychainManager
    private let coordinator: AppCoordinator

    init(keychainManager: KeychainManager, coordinator: AppCoordinator) {
        self.keychainManager = keychainManager
        self.coordinator = coordinator

        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        loadAPIKeyMasked()
    }

    private func loadAPIKeyMasked() {
        if let key = keychainManager.loadAPIKey() {
            let prefix = String(key.prefix(8))
            let suffix = String(key.suffix(4))
            apiKeyMasked = "\(prefix)••••••••\(suffix)"
        }
    }

    // MARK: - Actions
    func logout() {
        coordinator.onLogout()
    }

    func deleteAllData() {
        // Clear SwiftData
        // Clear Keychain
        // Reset UserDefaults
        coordinator.onLogout()
    }

    func openJulesDocs() {
        coordinator.present(.webView(
            url: URL(string: "https://jules.google.com/docs")!,
            title: "Jules Documentation"
        ))
    }

    func openPrivacyPolicy() {
        coordinator.present(.webView(
            url: URL(string: "https://policies.google.com/privacy")!,
            title: "Privacy Policy"
        ))
    }
}
```

### 15.2 View

```swift
// Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel(
        keychainManager: AppDependency.shared.keychainManager,
        coordinator: AppDependency.shared.coordinator
    )

    var body: some View {
        List {
            // Account Section
            Section {
                HStack {
                    Label("API Key", systemImage: "key")
                    Spacer()
                    Text(viewModel.apiKeyMasked)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }

                HStack {
                    Label("Plan", systemImage: "crown")
                    Spacer()
                    Text(viewModel.planTier)
                        .foregroundStyle(.secondary)
                }

                // Usage
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Daily Usage", systemImage: "chart.bar")
                        Spacer()
                        Text("\(viewModel.dailyTasksUsed)/\(viewModel.dailyTasksLimit)")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(
                        value: Double(viewModel.dailyTasksUsed),
                        total: Double(viewModel.dailyTasksLimit)
                    )
                    .tint(.joolsAccent)
                }
            } header: {
                Text("Account")
            }

            // Preferences Section
            Section {
                NavigationLink(value: Route.settingsAppearance) {
                    Label("Appearance", systemImage: "paintbrush")
                }
                NavigationLink(value: Route.settingsNotifications) {
                    Label("Notifications", systemImage: "bell")
                }
            } header: {
                Text("Preferences")
            }

            // Resources Section
            Section {
                Button(action: viewModel.openJulesDocs) {
                    Label("Jules Documentation", systemImage: "book")
                }
                Button(action: viewModel.openPrivacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            } header: {
                Text("Resources")
            }

            // About Section
            Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }

            // Danger Zone
            Section {
                Button(role: .destructive) {
                    viewModel.showLogoutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    viewModel.showDeleteDataConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            } header: {
                Text("Account Actions")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign Out",
            isPresented: $viewModel.showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                viewModel.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your API key again to use Jools.")
        }
        .confirmationDialog(
            "Delete All Data",
            isPresented: $viewModel.showDeleteDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                viewModel.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all local data including cached sessions. This cannot be undone.")
        }
    }
}
```

---

## 16. Loading, Empty & Error States

### 16.1 Skeleton Loading Views

```swift
// Core/Components/SkeletonView.swift
import SwiftUI

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: JoolsRadius.sm)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.1),
                        Color.gray.opacity(0.3)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Session Card Skeleton
struct SessionCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            HStack {
                SkeletonView(width: 200, height: 20)
                Spacer()
                SkeletonView(width: 80, height: 16)
            }
            SkeletonView(width: nil, height: 16)
            SkeletonView(width: 150, height: 14)
        }
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

// MARK: - Source Card Skeleton
struct SourceCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xs) {
            SkeletonView(width: 40, height: 40)
            SkeletonView(width: 120, height: 18)
            SkeletonView(width: 80, height: 14)
        }
        .frame(width: 140, height: 120)
        .padding()
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.md))
    }
}

// MARK: - Chat Message Skeleton
struct MessageSkeleton: View {
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                SkeletonView(width: CGFloat.random(in: 150...250), height: 40)
                SkeletonView(width: 60, height: 12)
            }

            if !isUser { Spacer(minLength: 80) }
        }
        .padding(.horizontal)
    }
}
```

### 16.2 Empty State Views

```swift
// Core/Components/EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Preset Empty States
extension EmptyStateView {
    static var noSessions: EmptyStateView {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No Sessions Yet",
            message: "Start a new session to let Jules help with your code.",
            actionTitle: "Create Session",
            action: nil // Set by parent
        )
    }

    static var noSources: EmptyStateView {
        EmptyStateView(
            icon: "folder.badge.plus",
            title: "No Repositories Connected",
            message: "Connect a GitHub repository to get started with Jules.",
            actionTitle: "Connect Repository",
            action: nil
        )
    }

    static var noActivities: EmptyStateView {
        EmptyStateView(
            icon: "text.bubble",
            title: "No Messages",
            message: "Send a message to start working with Jules.",
            actionTitle: nil,
            action: nil
        )
    }

    static var searchNoResults: EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            message: "Try adjusting your search terms.",
            actionTitle: nil,
            action: nil
        )
    }
}
```

### 16.3 Error State Views

```swift
// Core/Components/ErrorStateView.swift
import SwiftUI

struct ErrorStateView: View {
    let error: Error
    let retryAction: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(errorMessage)
        } actions: {
            if let retryAction {
                Button {
                    Task {
                        isRetrying = true
                        await retryAction()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Try Again")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
            }
        }
    }

    private var errorMessage: String {
        if let networkError = error as? NetworkError {
            return networkError.errorDescription ?? "Unknown error"
        }
        return error.localizedDescription
    }
}

// MARK: - Inline Error Banner
struct ErrorBanner: View {
    let message: String
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: JoolsSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.joolsCaption)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(JoolsSpacing.sm)
        .background(Color.joolsError)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
        .padding(.horizontal)
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    let message: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: JoolsSpacing.md) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                if let message {
                    Text(message)
                        .font(.joolsBody)
                        .foregroundStyle(.white)
                }
            }
            .padding(JoolsSpacing.xl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.lg))
        }
    }
}
```

### 16.4 Loading State Protocol

```swift
// Core/LoadingState.swift
enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case error(Error)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: Error? {
        if case .error(let error) = self { return error }
        return nil
    }
}

// MARK: - View Extension
extension View {
    @ViewBuilder
    func loadingState<T, Content: View, Empty: View>(
        _ state: LoadingState<T>,
        @ViewBuilder content: (T) -> Content,
        @ViewBuilder empty: () -> Empty,
        onRetry: (() async -> Void)? = nil
    ) -> some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let value):
            if let array = value as? any Collection, array.isEmpty {
                empty()
            } else {
                content(value)
            }
        case .error(let error):
            ErrorStateView(error: error, retryAction: onRetry)
        }
    }
}
```

---

## 17. Markdown Rendering

### 17.1 Markdown Parser

```swift
// Core/Markdown/MarkdownRenderer.swift
import SwiftUI
import Markdown

struct MarkdownRenderer: View {
    let content: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.sm) {
            ForEach(parseBlocks(), id: \.id) { block in
                renderBlock(block)
            }
        }
    }

    private func parseBlocks() -> [MarkdownBlock] {
        let document = Document(parsing: content)
        return document.children.enumerated().map { index, child in
            MarkdownBlock(id: index, markup: child)
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.markup {
        case let heading as Heading:
            renderHeading(heading)
        case let paragraph as Paragraph:
            renderParagraph(paragraph)
        case let codeBlock as CodeBlock:
            renderCodeBlock(codeBlock)
        case let list as UnorderedList:
            renderUnorderedList(list)
        case let list as OrderedList:
            renderOrderedList(list)
        case is ThematicBreak:
            Divider()
        default:
            Text(block.markup.format())
        }
    }

    @ViewBuilder
    private func renderHeading(_ heading: Heading) -> some View {
        let text = heading.plainText
        switch heading.level {
        case 1:
            Text(text).font(.title).fontWeight(.bold)
        case 2:
            Text(text).font(.title2).fontWeight(.semibold)
        case 3:
            Text(text).font(.title3).fontWeight(.medium)
        default:
            Text(text).font(.headline)
        }
    }

    private func renderParagraph(_ paragraph: Paragraph) -> some View {
        Text(attributedString(from: paragraph))
            .font(.joolsBody)
    }

    private func renderCodeBlock(_ codeBlock: CodeBlock) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(codeBlock.code)
                .font(.joolsCode)
                .padding(JoolsSpacing.sm)
        }
        .background(Color.joolsSurface)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
    }

    private func renderUnorderedList(_ list: UnorderedList) -> some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: JoolsSpacing.xs) {
                    Text("•")
                    Text(item.plainText)
                }
            }
        }
        .font(.joolsBody)
    }

    private func renderOrderedList(_ list: OrderedList) -> some View {
        VStack(alignment: .leading, spacing: JoolsSpacing.xxs) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: JoolsSpacing.xs) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                    Text(item.plainText)
                }
            }
        }
        .font(.joolsBody)
    }

    private func attributedString(from paragraph: Paragraph) -> AttributedString {
        var result = AttributedString()
        for child in paragraph.children {
            switch child {
            case let text as Markdown.Text:
                result += AttributedString(text.string)
            case let strong as Strong:
                var attr = AttributedString(strong.plainText)
                attr.font = .body.bold()
                result += attr
            case let emphasis as Emphasis:
                var attr = AttributedString(emphasis.plainText)
                attr.font = .body.italic()
                result += attr
            case let code as InlineCode:
                var attr = AttributedString(code.code)
                attr.font = .body.monospaced()
                attr.backgroundColor = Color.joolsSurface
                result += attr
            case let link as Markdown.Link:
                var attr = AttributedString(link.plainText)
                if let url = URL(string: link.destination ?? "") {
                    attr.link = url
                }
                result += attr
            default:
                result += AttributedString(child.format())
            }
        }
        return result
    }
}

struct MarkdownBlock: Identifiable {
    let id: Int
    let markup: any Markup
}

// MARK: - Markup Extensions
extension Markup {
    var plainText: String {
        if let text = self as? Markdown.Text {
            return text.string
        }
        return children.map { $0.plainText }.joined()
    }
}
```

### 17.2 Code Syntax Highlighting

```swift
// Core/Markdown/SyntaxHighlighter.swift
import SwiftUI

struct SyntaxHighlightedCode: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Language badge
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, JoolsSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.joolsSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.bottom, JoolsSpacing.xs)
                }

                // Code with line numbers
                HStack(alignment: .top, spacing: JoolsSpacing.sm) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...lineCount, id: \.self) { num in
                            Text("\(num)")
                                .font(.joolsCode)
                                .foregroundStyle(.tertiary)
                                .frame(height: lineHeight)
                        }
                    }
                    .padding(.trailing, JoolsSpacing.xs)
                    .border(width: 1, edges: [.trailing], color: .separator)

                    // Code
                    Text(highlightedCode)
                        .font(.joolsCode)
                        .textSelection(.enabled)
                }
            }
            .padding(JoolsSpacing.sm)
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: JoolsRadius.sm))
    }

    private var lineCount: Int {
        code.components(separatedBy: "\n").count
    }

    private var lineHeight: CGFloat { 20 }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.1)
            : Color(white: 0.96)
    }

    private var highlightedCode: AttributedString {
        // Basic keyword highlighting
        var result = AttributedString(code)

        let keywords = ["func", "var", "let", "if", "else", "for", "while", "return",
                        "class", "struct", "enum", "import", "guard", "switch", "case",
                        "async", "await", "try", "catch", "throws"]

        for keyword in keywords {
            if let range = result.range(of: "\\b\(keyword)\\b", options: .regularExpression) {
                result[range].foregroundColor = .purple
            }
        }

        return result
    }
}
```

---

## 18. Offline Mode Specification

### 18.1 Offline Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         OFFLINE ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐         │
│  │   SwiftData   │     │   Sync Queue  │     │   Network     │         │
│  │   (Source of  │◀───▶│   (Pending    │◀───▶│   Monitor     │         │
│  │    Truth)     │     │    Actions)   │     │               │         │
│  └───────────────┘     └───────────────┘     └───────────────┘         │
│         │                     │                     │                   │
│         ▼                     ▼                     ▼                   │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐         │
│  │   UI Layer    │     │   Conflict    │     │   Reachability│         │
│  │   (Reads)     │     │   Resolution  │     │   Banner      │         │
│  └───────────────┘     └───────────────┘     └───────────────┘         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 18.2 Network Monitor

```swift
// Core/Network/NetworkMonitor.swift
import Network
import Combine

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }

    init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }

    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .unknown
    }
}

// MARK: - Offline Banner
struct OfflineBanner: View {
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: JoolsSpacing.xs) {
                Image(systemName: "wifi.slash")
                Text("You're offline")
                Spacer()
                Text("Changes will sync when connected")
                    .font(.caption)
            }
            .font(.joolsCaption)
            .foregroundStyle(.white)
            .padding(JoolsSpacing.sm)
            .background(Color.gray)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
```

### 18.3 Sync Queue

```swift
// Core/Sync/SyncQueue.swift
import SwiftData

@Model
final class PendingAction {
    @Attribute(.unique) var id: UUID
    var actionType: String
    var payload: Data
    var createdAt: Date
    var retryCount: Int
    var lastError: String?

    init(actionType: String, payload: Data) {
        self.id = UUID()
        self.actionType = actionType
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
    }
}

@MainActor
final class SyncQueue {
    private let modelContainer: ModelContainer
    private let apiClient: APIClient
    private let networkMonitor: NetworkMonitor

    private var syncTask: Task<Void, Never>?

    init(modelContainer: ModelContainer, apiClient: APIClient, networkMonitor: NetworkMonitor) {
        self.modelContainer = modelContainer
        self.apiClient = apiClient
        self.networkMonitor = networkMonitor

        observeNetworkChanges()
    }

    // MARK: - Queue Actions
    func enqueue<T: Encodable>(action: String, payload: T) async throws {
        let data = try JSONEncoder().encode(payload)
        let pending = PendingAction(actionType: action, payload: data)

        let context = modelContainer.mainContext
        context.insert(pending)
        try context.save()

        // Try immediate sync if online
        if networkMonitor.isConnected {
            await processQueue()
        }
    }

    // MARK: - Process Queue
    func processQueue() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<PendingAction>(
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for action in pending {
            do {
                try await processAction(action)
                context.delete(action)
                try context.save()
            } catch {
                action.retryCount += 1
                action.lastError = error.localizedDescription
                try? context.save()

                // Stop processing if we hit a network error
                if error is NetworkError { break }
            }
        }
    }

    private func processAction(_ action: PendingAction) async throws {
        switch action.actionType {
        case "sendMessage":
            let payload = try JSONDecoder().decode(SendMessagePayload.self, from: action.payload)
            try await apiClient.sendMessage(sessionId: payload.sessionId, message: payload.message)
        case "approvePlan":
            let payload = try JSONDecoder().decode(ApprovePlanPayload.self, from: action.payload)
            try await apiClient.approvePlan(sessionId: payload.sessionId)
        default:
            break
        }
    }

    private func observeNetworkChanges() {
        // When network becomes available, process queue
        Task {
            while true {
                try? await Task.sleep(for: .seconds(5))
                if networkMonitor.isConnected {
                    await processQueue()
                }
            }
        }
    }
}

// MARK: - Payloads
struct SendMessagePayload: Codable {
    let sessionId: String
    let message: String
}

struct ApprovePlanPayload: Codable {
    let sessionId: String
}
```

### 18.4 Offline Behavior by Feature

| Feature | Offline Behavior |
|---------|------------------|
| **Dashboard** | Shows cached data, stale indicator |
| **Session List** | Shows cached sessions |
| **Chat** | Read cached messages, queue new messages |
| **Send Message** | Optimistically added, queued for sync |
| **Approve Plan** | Queued for sync, disabled until online |
| **Create Session** | Disabled (requires server) |
| **Settings** | Fully functional |

---

## 19. Project Configuration

### 19.1 Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>Jools</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <true/>
    </dict>
    <key>UILaunchScreen</key>
    <dict>
        <key>UIColorName</key>
        <string>LaunchBackground</string>
        <key>UIImageName</key>
        <string>LaunchLogo</string>
    </dict>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>jools</string>
            </array>
            <key>CFBundleURLName</key>
            <string>com.jools.app</string>
        </dict>
    </array>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.jools.refresh</string>
    </array>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
```

### 19.2 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:jules.google.com</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.jools.app</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.jools.app</string>
    </array>
</dict>
</plist>
```

### 19.3 Build Configuration

```swift
// Project.swift (if using Tuist) or Xcode settings
// Build Settings:
// - SWIFT_VERSION = 6.0
// - IPHONEOS_DEPLOYMENT_TARGET = 26.0
// - SWIFT_STRICT_CONCURRENCY = complete
// - ENABLE_USER_SCRIPT_SANDBOXING = YES
// - CODE_SIGN_STYLE = Automatic
// - DEVELOPMENT_TEAM = <Your Team ID>
```

---

## 20. Accessibility Guidelines

### 20.1 VoiceOver Support

```swift
// MARK: - Accessibility Modifiers
extension View {
    func accessibleSessionCard(
        title: String,
        state: SessionState,
        repository: String
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(state.accessibilityDescription), in \(repository)")
            .accessibilityHint("Double tap to open session details")
            .accessibilityAddTraits(.isButton)
    }

    func accessibleMessageBubble(
        isUser: Bool,
        message: String,
        time: Date
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(isUser ? "You" : "Jules") said: \(message), at \(time.formatted(date: .omitted, time: .shortened))")
    }
}

// MARK: - Session State Accessibility
extension SessionState {
    var accessibilityDescription: String {
        switch self {
        case .unspecified: return "status unknown"
        case .queued: return "waiting in queue"
        case .running: return "currently running"
        case .awaitingUserInput: return "waiting for your input"
        case .completed: return "completed successfully"
        case .failed: return "failed with error"
        case .cancelled: return "cancelled"
        }
    }
}
```

### 20.2 Dynamic Type Support

```swift
// MARK: - Scaled Metrics
struct ScaledMetrics {
    @ScaledMetric(relativeTo: .body) var bubblePadding: CGFloat = 12
    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) var badgeSize: CGFloat = 8
}

// Usage in views
struct AccessibleMessageBubble: View {
    let message: String
    @ScaledMetric private var padding: CGFloat = 12
    @ScaledMetric private var cornerRadius: CGFloat = 16

    var body: some View {
        Text(message)
            .padding(padding)
            .background(Color.joolsBubbleUser)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
```

### 20.3 Accessibility Checklist

| Feature | Requirement | Implementation |
|---------|-------------|----------------|
| **VoiceOver Labels** | All interactive elements labeled | `.accessibilityLabel()` |
| **VoiceOver Hints** | Actions have hints | `.accessibilityHint()` |
| **Dynamic Type** | Text scales with system setting | `@ScaledMetric`, `.font(.body)` |
| **Color Contrast** | 4.5:1 minimum ratio | Design tokens verified |
| **Reduce Motion** | Respect system setting | `@Environment(\.accessibilityReduceMotion)` |
| **Button Targets** | Minimum 44x44pt | `.frame(minWidth: 44, minHeight: 44)` |
| **Focus Order** | Logical reading order | `.accessibilitySortPriority()` |
| **Error Announcements** | Errors announced | `AccessibilityNotification.post()` |

### 20.4 Reduce Motion Support

```swift
struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? .none : .joolsSpring, value: UUID())
    }
}

extension View {
    func reduceMotionAware() -> some View {
        modifier(ReduceMotionAware())
    }
}

// Usage
SessionCard(session: session)
    .reduceMotionAware()
```

---

## 21. HTML UI Mocks

Interactive HTML mockups are provided in the `docs/mocks/` directory. These follow Apple Human Interface Guidelines and iOS 26 design language with:

- **Dark Mode First:** All designs optimized for dark appearance
- **Dynamic Island:** Proper safe area handling
- **SF Pro Typography:** System fonts with proper weights
- **iOS 26 Visual Language:** Glassmorphism, depth, and subtle animations
- **Accessibility Ready:** Proper contrast ratios and touch targets

### 21.1 Available Mocks

| Screen | File | Description |
|--------|------|-------------|
| **Onboarding** | `mocks/onboarding.html` | API key entry with animated gradient background |
| **Dashboard** | `mocks/dashboard.html` | Main screen with usage stats, sources, and sessions |
| **Chat** | `mocks/chat.html` | Session conversation with plan approval UI |
| **Settings** | `mocks/settings.html` | Grouped list settings with iOS styling |

### 21.2 Design System Tokens (CSS)

```css
:root {
    /* Primary Colors */
    --accent: #007AFF;
    --green: #34C759;
    --orange: #FF9500;
    --red: #FF3B30;
    --purple: #5856D6;

    /* Backgrounds */
    --background: #000000;
    --surface: rgba(255, 255, 255, 0.08);
    --surface-elevated: #1C1C1E;

    /* Text */
    --text-primary: #FFFFFF;
    --text-secondary: rgba(255, 255, 255, 0.6);
    --text-tertiary: rgba(255, 255, 255, 0.4);

    /* Borders */
    --border: rgba(255, 255, 255, 0.1);
    --separator: rgba(255, 255, 255, 0.08);

    /* Radii */
    --radius-sm: 8px;
    --radius-md: 12px;
    --radius-lg: 16px;
    --radius-xl: 24px;
}
```

### 21.3 Viewing the Mocks

Open the HTML files directly in a browser:

```bash
# From project root
open docs/mocks/onboarding.html
open docs/mocks/dashboard.html
open docs/mocks/chat.html
open docs/mocks/settings.html
```

---

## 22. Appendices

### A. References

- **Jules API Documentation:** https://jules.google.com/docs/api/reference/
- **Jules Quickstart:** https://jules.google.com/docs/api/
- **SwiftUI Documentation:** https://developer.apple.com/documentation/swiftui
- **SwiftData Documentation:** https://developer.apple.com/documentation/swiftdata
- **Human Interface Guidelines:** https://developer.apple.com/design/human-interface-guidelines/

### B. AGENTS.md Support

Jules automatically reads `AGENTS.md` from repository roots. Consider creating a template for users to add to their repos for better Jools integration.

### C. Rate Limit Handling

When receiving a 429 response, implement exponential backoff:

```swift
func withRetry<T>(
    maxAttempts: Int = 3,
    delay: TimeInterval = 1.0,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch NetworkError.rateLimited {
            lastError = NetworkError.rateLimited
            let backoff = delay * pow(2.0, Double(attempt))
            try await Task.sleep(for: .seconds(backoff))
        } catch {
            throw error
        }
    }

    throw lastError!
}
```

### D. Changelog

- **v2.0** (2025-12-16): Complete rewrite with verified API documentation
  - Added comprehensive API reference from official docs
  - Added usage limits and plan tiers
  - Fixed session states and activity types
  - Added automation mode support
  - Added AGENTS.md support note
  - Expanded SwiftData schema
  - Added polling service implementation
  - Added component library
  - Restructured implementation phases

---

*Document verified against official Jules documentation from jules.google.com (December 2025)*

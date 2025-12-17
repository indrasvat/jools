// JoolsKit - Core framework for the Jools iOS app
// A client for Google's Jules coding agent API

/// JoolsKit provides the core networking, models, and services for interacting
/// with the Jules API.
///
/// ## Overview
///
/// JoolsKit is organized into several modules:
///
/// - **API**: Network client and endpoint definitions
/// - **Models**: Data transfer objects and domain models
/// - **Auth**: Keychain management for secure credential storage
/// - **Polling**: Adaptive polling service for real-time updates
///
/// ## Getting Started
///
/// ```swift
/// // Initialize the keychain manager
/// let keychain = KeychainManager()
///
/// // Save your API key
/// try keychain.saveAPIKey("your-jules-api-key")
///
/// // Create the API client
/// let api = APIClient(keychain: keychain)
///
/// // List sources
/// let sources = try await api.listSources()
/// ```

// Re-export all public types
@_exported import Foundation

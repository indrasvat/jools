// Auto-generated file - do not edit
import Foundation

enum BuildInfo {
    static let gitSHA = "a8ff5ff"
    static let gitBranch = "create-jools"
    static let buildDate = "2025-12-18 08:21 UTC"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    static var fullVersion: String {
        "\(version) (\(build))"
    }

    static var debugDescription: String {
        "\(fullVersion) • \(gitSHA) • \(gitBranch)"
    }
}

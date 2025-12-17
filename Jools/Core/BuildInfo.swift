// Auto-generated file - do not edit
import Foundation

enum BuildInfo {
    static let gitSHA = "1ad907c"
    static let gitBranch = "create-jools"
    static let buildDate = "2025-12-17 08:50 UTC"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    static var fullVersion: String {
        "\(version) (\(build))"
    }

    static var debugDescription: String {
        "\(fullVersion) • \(gitSHA) • \(gitBranch)"
    }
}

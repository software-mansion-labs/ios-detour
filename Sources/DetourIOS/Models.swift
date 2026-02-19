import Foundation

public struct DetourConfig {
    public let apiKey: String
    public let appId: String
    public let shouldUseClipboard: Bool

    public init(apiKey: String, appId: String, shouldUseClipboard: Bool = true) {
        self.apiKey = apiKey
        self.appId = appId
        self.shouldUseClipboard = shouldUseClipboard
    }
}

struct ProbabilisticFingerprint: Codable {
    let platform: String
    let model: String
    let manufacturer: String
    let systemVersion: String
    let screenWidth: Double
    let screenHeight: Double
    let scale: Double
    let locale: [LocaleTag]
    let timezone: String
    let userAgent: String
    let timestamp: Int64
    let pastedLink: String?
}

struct LocaleTag: Codable {
    let languageTag: String
}

public struct DetourResult {
    public let processed: Bool
    public let link: URL?
    public let route: String?
    
    public init(processed: Bool, link: URL?, route: String?) {
            self.processed = processed
            self.link = link
            self.route = route
        }

    public static func empty() -> DetourResult {
        return DetourResult(processed: true, link: nil, route: nil)
    }
}

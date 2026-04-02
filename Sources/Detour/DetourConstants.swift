import Foundation

enum DetourConstants {
    static let sdkType = "ios"
    static let sdkVersion = "1.0.1"
    static let sdkHeaderField = "X-SDK"
    static let sdkHeaderValue = "\(sdkType)/\(sdkVersion)"
    static let apiUrl: URL? = URL(string: "https://godetour.dev/api/link/match-link")
    static let resolveShortUrl: URL? = URL(string: "https://godetour.dev/api/link/resolve-short")
    static let analyticsEventUrl: URL? = URL(string: "https://godetour.dev/api/analytics/event")
    static let analyticsRetentionUrl: URL? = URL(string: "https://godetour.dev/api/analytics/retention")
}

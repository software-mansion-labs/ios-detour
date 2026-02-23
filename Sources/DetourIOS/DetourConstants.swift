import Foundation

enum DetourConstants {
    static let apiUrl: URL? = URL(string: "https://godetour.app/api/link/match-link")
    static let resolveShortUrl: URL? = URL(string: "https://godetour.app/api/link/resolve-short")
    static let analyticsEventUrl: URL? = URL(string: "https://godetour.app/api/analytics/event")
    static let analyticsRetentionUrl: URL? = URL(string: "https://godetour.app/api/analytics/retention")
}

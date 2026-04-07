import Foundation

enum DetourConstants {
    static let sdkType = "ios"
    static let sdkVersion: String = {
            let bundle = Bundle(for: Detour.self)
            let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            return version ?? "0.0.0"
        }()
    static let sdkHeaderField = "X-SDK"
    static let sdkHeaderValue = "\(sdkType)/\(sdkVersion)"
    static let apiUrl: URL? = URL(string: "https://godetour.dev/api/link/match-link")
    static let resolveShortUrl: URL? = URL(string: "https://godetour.dev/api/link/resolve-short")
    static let analyticsEventUrl: URL? = URL(string: "https://godetour.dev/api/analytics/event")
    static let analyticsRetentionUrl: URL? = URL(string: "https://godetour.dev/api/analytics/retention")
}

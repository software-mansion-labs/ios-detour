import Foundation

enum DetourEndpoint: String, CaseIterable {
    case matchLink = "api/link/match-link"
    case resolveShort = "api/link/resolve-short"
    case universalLinkClick = "api/link/universal-link-click"
    case analyticsEvent = "api/analytics/event"
    case analyticsRetention = "api/analytics/retention"
}

enum DetourEndpoints {
    private static let tag = "DetourEndpoints"

    static let defaultBaseURL = URL(string: "https://godetour.dev")!

    private static let lock = NSLock()
    private static var reportedBaseURLs = Set<URL>()

    // MMP-DECISION: an invalid baseURL blocks requests instead of falling back to production,
    // so test traffic never reaches production data. Own choice; MMP-06 cz. 1 only says "rejected with a log error".
    /// Returns nil when `config.baseURL` is not an https URL, so no request leaves the device.
    static func url(_ endpoint: DetourEndpoint, config: DetourConfig) -> URL? {
        guard let baseURL = resolveBaseURL(config.baseURL) else { return nil }
        return baseURL.appendingPathComponent(endpoint.rawValue)
    }

    private static func resolveBaseURL(_ configured: URL?) -> URL? {
        guard let configured, configured != defaultBaseURL else { return defaultBaseURL }

        let isValid = configured.scheme?.lowercased() == "https" && configured.host?.isEmpty == false
        // MMP-DECISION: logged once per process on the first request, not in an explicit start step.
        // MMP-06 cz. 1 asks for a warning "at startup"; move it to configure()/start() once cz. 5 adds them.
        reportOnce(configured) {
            if isValid {
                DetourLogger.warn(tag, "[Detour:CONFIG] Using custom baseURL \(configured.absoluteString). Remove it before releasing to production.")
            } else {
                DetourLogger.error(tag, "[Detour:CONFIG] Invalid baseURL \(configured.absoluteString): only https URLs are allowed. Requests are not sent.")
            }
        }
        return isValid ? configured : nil
    }

    private static func reportOnce(_ baseURL: URL, _ report: () -> Void) {
        lock.lock()
        let isFirst = reportedBaseURLs.insert(baseURL).inserted
        lock.unlock()
        if isFirst { report() }
    }
}

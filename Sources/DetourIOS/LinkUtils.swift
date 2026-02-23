import Foundation

class LinkUtils {
    static func getRestOfPath(_ pathname: String) -> String {
        // Safety check: needs at least 2 chars (e.g. "/a") to possibly have a second slash
        if pathname.count < 2 { return "/" }

        let searchStartIndex = pathname.index(pathname.startIndex, offsetBy: 1)

        // Find the index of the second slash
        if let secondSlashIndex = pathname[searchStartIndex...].firstIndex(of: "/") {
            // Return everything from that slash onwards
            return String(pathname[secondSlashIndex...])
        }

        // If no second slash found return root
        return "/"
    }

    static func isInfrastructureUrl(_ rawUrl: String) -> Bool {
        if rawUrl.isEmpty {
            return true
        }

        if rawUrl.contains("expo-development-client") { return true }
        if rawUrl.hasPrefix("exp://") || rawUrl.hasPrefix("exps://") { return true }
        if rawUrl == "about:blank" { return true }

        return false
    }

    private static func routeFromWebUrl(_ url: URL) -> String {
        let fullPath = url.path
        var finalRoute = getRestOfPath(fullPath)

        if let query = url.query {
            finalRoute += "?\(query)"
        }

        return finalRoute
    }

    static func routeFromDeepLink(_ url: URL) -> String {
        let host = url.host ?? ""
        let route = host + url.path + (url.query.map { "?\($0)" } ?? "")
        return route.hasPrefix("/") ? route : "/\(route)"
    }

    static func extractRoute(from url: URL) -> String {
        let isWebUrl = url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        return isWebUrl ? routeFromWebUrl(url) : routeFromDeepLink(url)
    }

    static func normalizeRawLink(_ rawLink: String) -> String {
        if rawLink.hasPrefix("//") {
            return "https:\(rawLink)"
        }
        return rawLink
    }

    static func looksLikeUrl(_ rawLink: String) -> Bool {
        return rawLink.contains("://") || rawLink.hasPrefix("//")
    }

    static func detectLinkType(from url: URL, override: LinkType? = nil) -> LinkType {
        if let override {
            return override
        }

        let isWebUrl = url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        return isWebUrl ? .verified : .scheme
    }

    static func extractRoute(from rawLink: String) -> String {
        if !looksLikeUrl(rawLink) {
            return rawLink.hasPrefix("/") ? rawLink : "/\(rawLink)"
        }

        let normalized = normalizeRawLink(rawLink)
        guard let parsedUrl = URL(string: normalized) else {
            return rawLink
        }

        return extractRoute(from: parsedUrl)
    }
}

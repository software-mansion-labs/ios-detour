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

        if rawUrl == "about:blank" { return true }

        return false
    }

    // url.host and url.path are percent-decoded, so an encoded '?' or '/' would become a delimiter.
    // URLComponents keeps them encoded, as the Android and RN SDKs do.
    private static func encodedParts(of url: URL) -> (host: String, path: String, query: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url.host ?? "", url.path, url.query ?? "")
        }
        let port = components.port.map { ":\($0)" } ?? ""
        return ((components.percentEncodedHost ?? "") + port, components.percentEncodedPath, components.percentEncodedQuery ?? "")
    }

    private static func routeFromWebUrl(_ url: URL) -> String {
        let parts = encodedParts(of: url)
        let pathname = getRestOfPath(parts.path)
        return parts.query.isEmpty ? pathname : "\(pathname)?\(parts.query)"
    }

    static func routeFromDeepLink(_ url: URL) -> String {
        let parts = encodedParts(of: url)
        let route = parts.host + parts.path + (parts.query.isEmpty ? "" : "?\(parts.query)")
        return route.hasPrefix("/") ? route : "/\(route)"
    }

    static func extractRoute(from url: URL) -> String {
        return isWebUrl(url.absoluteString, parsedUrl: url) ? routeFromWebUrl(url) : routeFromDeepLink(url)
    }

    static func normalizeRawLink(_ rawLink: String) -> String {
        if rawLink.hasPrefix("//") {
            return "https:\(rawLink)"
        }
        return rawLink
    }

    // Only a scheme before the first ':' makes this a URL, so "/hash/p?redirect=https://x" stays a path.
    static func looksLikeUrl(_ rawLink: String) -> Bool {
        return rawLink.hasPrefix("//") || rawLink.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
    }

    // Query of a full link string without the fragment. Unlike URL(string:), it also works with a stray '%'.
    static func rawQuery(of link: String) -> String? {
        let withoutFragment = link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let queryStart = withoutFragment.firstIndex(of: "?") else { return nil }
        return String(withoutFragment[withoutFragment.index(after: queryStart)...])
    }

    static func detectLinkType(from url: URL, override: LinkType? = nil) -> LinkType {
        if let override {
            return override
        }

        return isWebUrl(url.absoluteString, parsedUrl: url) ? .verified : .scheme
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

    static func isWebUrl(_ rawLink: String, parsedUrl: URL? = nil) -> Bool {
        if rawLink.hasPrefix("//") { return true }
        if let parsedUrl {
            let scheme = parsedUrl.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
        return rawLink.lowercased().hasPrefix("http://") || rawLink.lowercased().hasPrefix("https://")
    }

    static func parseParams(from query: String?) -> [String: String] {
        guard let query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = components.first else { continue }
            let key = decodeQueryComponent(String(rawKey))
            let value = components.count > 1 ? decodeQueryComponent(String(components[1])) : ""
            result[key] = value
        }
        return result
    }

    // Match URLSearchParams: '+' is a space, and a '%' that doesn't start an escape stays as text.
    private static func decodeQueryComponent(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        let escaped = spaced.replacingOccurrences(of: "%(?![0-9A-Fa-f]{2})", with: "%25", options: .regularExpression)
        return escaped.removingPercentEncoding ?? spaced
    }

    static func makeDetourLink(from url: URL, type: LinkType) -> DetourLink {
        let route = extractRoute(from: url)
        let pathname = route.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? route
        return DetourLink(
            url: url.absoluteString,
            route: route,
            pathname: pathname.isEmpty ? "/" : pathname,
            params: parseParams(from: url.query),
            type: type
        )
    }

    static func makeDetourLink(fromPath rawPath: String, type: LinkType) -> DetourLink {
        let normalized = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        // Drop the fragment, as URL parsing does for full links.
        let withoutFragment = normalized.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let fullPathname = parts.first ?? "/"
        let query = parts.count > 1 ? parts[1] : ""

        let pathname = getRestOfPath(fullPathname)
        let route = query.isEmpty ? pathname : "\(pathname)?\(query)"

        return DetourLink(
            url: normalized,
            route: route,
            pathname: pathname,
            params: parseParams(from: query),
            type: type
        )
    }
}

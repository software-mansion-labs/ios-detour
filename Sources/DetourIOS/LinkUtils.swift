import Foundation

class LinkUtils {
    private static func getRestOfPath(_ pathname: String) -> String {
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

    static func extractRoute(from url: URL) -> String {
        let fullPath = url.path

        var finalRoute = getRestOfPath(fullPath)

        if let query = url.query {
            finalRoute += "?\(query)"
        }

        return finalRoute
    }
}

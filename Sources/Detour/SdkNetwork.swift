import Foundation

/// Requests to the `api/sdk/*` endpoints.
enum SdkNetwork {
    private static let tag = "SdkApiClient"

    static func fetchConfig(config: DetourConfig, etag: String?) async -> SdkConfigStore.FetchResult {
        guard let url = DetourEndpoints.url(.sdkConfig, config: config) else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        DetourNetwork.applyHeaders(to: &request, config: config)
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        // The SDK keeps its own copy and sends the ETag itself.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failed }

            switch httpResponse.statusCode {
            case 200:
                return .updated(body: data, etag: httpResponse.value(forHTTPHeaderField: "ETag"))
            case 304:
                return .notModified
            default:
                DetourLogger.warn(tag, "[Detour:CONFIG] sdk/config fetch failed: \(httpResponse.statusCode); using the last config.")
                return .failed
            }
        } catch {
            DetourLogger.warn(tag, "[Detour:CONFIG] sdk/config fetch exception: \(error.localizedDescription); using the last config.")
            return .failed
        }
    }
}

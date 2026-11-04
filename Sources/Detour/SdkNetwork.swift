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

    static func sendConsent(
        _ consent: DetourConsent,
        consentText: String?,
        config: DetourConfig,
        deviceID: String,
        userID: String?
    ) async {
        guard let consentFields = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(consent)) else { return }

        var body: [String: Any] = ["device_id": deviceID, "consent": consentFields]
        body["user_id"] = userID
        body["consent_text"] = consentText

        guard let status = await post(.sdkConsent, body: body, config: config) else { return }
        if !(200 ... 299).contains(status) {
            DetourLogger.warn(tag, "[Detour:CONSENT] sdk/consent send failed: \(status)")
        }
    }

    static func sendKillSwitch(enabled: Bool, at date: Date, config: DetourConfig, deviceID: String) async -> KillSwitchReporter.Outcome {
        let body: [String: Any] = [
            "device_id": deviceID,
            "disabled": !enabled,
            "timestamp": ISOTimestamp.string(from: date),
        ]
        guard DetourEndpoints.url(.sdkDisable, config: config) != nil else { return .stop }
        // The server stops writing about 28 s after a request starts, so a request given up
        // after 60 s can no longer land after the next one.
        guard let status = await post(.sdkDisable, body: body, config: config, timeout: 60) else { return .retry }

        switch status {
        case 200 ... 299:
            return .confirmed
        case 429, 500...:
            return .retry
        default:
            DetourLogger.error(tag, "[Detour:KILL_SWITCH] sdk/disable rejected: \(status); sent again on the next launch.")
            return .stop
        }
    }

    /// The response status, or nil when no response arrived.
    static func post(
        _ endpoint: DetourEndpoint,
        body: [String: Any],
        config: DetourConfig,
        timeout: TimeInterval? = nil
    ) async -> Int? {
        guard let url = DetourEndpoints.url(endpoint, config: config),
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout {
            request.timeoutInterval = timeout
        }
        DetourNetwork.applyHeaders(to: &request, config: config)
        request.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] \(endpoint.rawValue) exception: \(error.localizedDescription)")
            return nil
        }
    }
}

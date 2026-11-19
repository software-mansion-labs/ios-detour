import Foundation

/// Requests to the `api/sdk/*` endpoints.
enum SdkNetwork {
    private static let tag = "SdkApiClient"

    static func fetchConfig(config: DetourConfig, sdkPackage: SdkPackage, etag: String?) async -> DetourFetchResult {
        await get(.sdkConfig, config: config, sdkPackage: sdkPackage, etag: etag)
    }

    static func fetchConversionValueSchema(config: DetourConfig, sdkPackage: SdkPackage, etag: String?) async -> DetourFetchResult {
        await get(.conversionValueSchema, config: config, sdkPackage: sdkPackage, etag: etag)
    }

    private static func get(
        _ endpoint: DetourEndpoint,
        config: DetourConfig,
        sdkPackage: SdkPackage,
        etag: String?
    ) async -> DetourFetchResult {
        guard let url = DetourEndpoints.url(endpoint, config: config) else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        DetourNetwork.applyHeaders(to: &request, config: config, sdkPackage: sdkPackage)
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
                DetourLogger.warn(tag, "[Detour:CONFIG] \(endpoint.rawValue) fetch failed: \(httpResponse.statusCode); using the last copy.")
                return .failed
            }
        } catch {
            DetourLogger.warn(tag, "[Detour:CONFIG] \(endpoint.rawValue) fetch exception: \(error.localizedDescription); using the last copy.")
            return .failed
        }
    }

    /// True when the server confirmed the consent.
    static func sendConsent(
        _ consent: DetourConsent,
        consentText: String?,
        config: DetourConfig,
        sdkPackage: SdkPackage,
        deviceID: String,
        userID: String?
    ) async -> Bool {
        guard let body = consentBody(consent, consentText: consentText, deviceID: deviceID, userID: userID) else { return false }

        guard let status = await post(.sdkConsent, body: body, config: config, sdkPackage: sdkPackage) else { return false }
        if !(200 ... 299).contains(status) {
            DetourLogger.warn(tag, "[Detour:CONSENT] sdk/consent send failed: \(status)")
            return false
        }
        return true
    }

    static func consentBody(_ consent: DetourConsent, consentText: String?, deviceID: String, userID: String?) -> [String: Any]? {
        guard let consentFields = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(consent)) else { return nil }

        var body: [String: Any] = ["device_id": deviceID, "consent": consentFields]
        body["user_id"] = userID
        // The server rejects the whole consent for an empty text.
        if let consentText, !consentText.isEmpty {
            body["consent_text"] = consentText
        }
        return body
    }

    static func sendKillSwitch(enabled: Bool, at date: Date, config: DetourConfig, sdkPackage: SdkPackage, deviceID: String) async -> KillSwitchReporter.Outcome {
        let body: [String: Any] = [
            "device_id": deviceID,
            "disabled": !enabled,
            "timestamp": ISOTimestamp.string(from: date),
        ]
        guard DetourEndpoints.url(.sdkDisable, config: config) != nil else { return .stop }
        // The server stops writing about 28 s after a request starts, so a request given up
        // after 60 s can no longer land after the next one.
        guard let status = await post(.sdkDisable, body: body, config: config, sdkPackage: sdkPackage, timeout: 60) else { return .retry }

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
        sdkPackage: SdkPackage,
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
        DetourNetwork.applyHeaders(to: &request, config: config, sdkPackage: sdkPackage)
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

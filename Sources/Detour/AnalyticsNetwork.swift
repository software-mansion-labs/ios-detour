import Foundation

enum AnalyticsNetwork {
    private static let tag = "AnalyticsApiClient"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func timestamp(_ date: Date = Date()) -> String {
        return timestampFormatter.string(from: date)
    }

    private static func endpoint(of request: AnalyticsRequest) -> DetourEndpoint {
        switch request {
        case .event: return .analyticsEvent
        case .retention: return .analyticsRetention
        case .session: return .analyticsSession
        }
    }

    private static func fields(of request: AnalyticsRequest) -> [String: Any] {
        switch request {
        case let .event(name, data):
            var fields: [String: Any] = ["event_name": name, "timestamp": timestamp(), "platform": "ios"]
            if let data, JSONSerialization.isValidJSONObject(data) {
                fields["data"] = data
            }
            return fields
        case let .retention(name):
            return ["event_name": name, "timestamp": timestamp(), "platform": "ios"]
        case let .session(.start(sessionID, at)):
            return ["type": "start", "session_id": sessionID, "timestamp": timestamp(at)]
        case let .session(.end(sessionID, at, duration)):
            return [
                "type": "end",
                "session_id": sessionID,
                "timestamp": timestamp(at),
                "duration_ms": Int((duration * 1000).rounded()),
            ]
        }
    }

    /// Context, then the request's own fields, which win on a shared name, then the identity.
    static func body(of request: AnalyticsRequest, deviceID: String, userID: String?) -> [String: Any] {
        var body = RequestContext.current().dictionary
        body.merge(fields(of: request)) { _, own in own }
        body["device_id"] = deviceID
        if let userID {
            body["user_id"] = userID
        }
        return body
    }

    static func send(_ request: AnalyticsRequest, config: DetourConfig, deviceID: String, userID: String?) async {
        let endpoint = endpoint(of: request)
        guard let url = DetourEndpoints.url(endpoint, config: config) else { return }

        let body = body(of: request, deviceID: deviceID, userID: userID)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            DetourLogger.warn(tag, "[Detour:ANALYTICS] Failed to encode \(endpoint.rawValue) body.")
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        DetourNetwork.applyHeaders(to: &urlRequest, config: config)
        urlRequest.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                DetourLogger.warn(tag, "[Detour:ANALYTICS] \(endpoint.rawValue) send failed: \(httpResponse.statusCode)")
            }
        } catch {
            DetourLogger.warn(tag, "[Detour:ANALYTICS] \(endpoint.rawValue) send exception: \(error.localizedDescription)")
        }
    }
}

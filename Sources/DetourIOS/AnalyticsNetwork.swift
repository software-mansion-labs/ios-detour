import Foundation

enum AnalyticsNetwork {
    private static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func baseRequest(
        url: URL?,
        config: DetourConfig
    ) -> URLRequest? {
        guard let url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appId, forHTTPHeaderField: "X-App-ID")
        return request
    }

    private static func commonBody(eventName: String, deviceID: String) -> [String: Any] {
        return [
            "event_name": eventName,
            "timestamp": makeTimestamp(),
            "platform": "ios",
            "device_id": deviceID,
        ]
    }

    static func sendEvent(config: DetourConfig, eventName: String, data: [String: Any]?, deviceID: String) async {
        guard var request = baseRequest(url: DetourConstants.analyticsEventUrl, config: config) else {
            return
        }

        var body = commonBody(eventName: eventName, deviceID: deviceID)
        if let data, JSONSerialization.isValidJSONObject(data) {
            body["data"] = data
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            print("🔗[Detour:ANALYTICS_ERROR] Failed to encode event body.")
            return
        }

        request.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                print("🔗[Detour:ANALYTICS_ERROR] Failed to log event: \(httpResponse.statusCode)")
            }
        } catch {
            print("🔗[Detour:ANALYTICS_ERROR] Network error logging event: \(error.localizedDescription)")
        }
    }

    static func sendRetentionEvent(config: DetourConfig, eventName: String, deviceID: String) async {
        guard var request = baseRequest(url: DetourConstants.analyticsRetentionUrl, config: config) else {
            return
        }

        let body = commonBody(eventName: eventName, deviceID: deviceID)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            print("🔗[Detour:ANALYTICS_ERROR] Failed to encode retention event body.")
            return
        }

        request.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                print("🔗[Detour:ANALYTICS_ERROR] Failed to log retention event: \(httpResponse.statusCode)")
            }
        } catch {
            print("🔗[Detour:ANALYTICS_ERROR] Network error logging retention event: \(error.localizedDescription)")
        }
    }
}

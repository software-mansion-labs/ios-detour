import Foundation

enum AnalyticsNetwork {
    private static let tag = "AnalyticsApiClient"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeTimestamp() -> String {
        return timestampFormatter.string(from: Date())
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
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(DetourConstants.sdkHeaderValue, forHTTPHeaderField: DetourConstants.sdkHeaderField)
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

    private static func send(
        config: DetourConfig,
        url: URL?,
        eventName: String,
        deviceID: String,
        data: [String: Any]?,
        kind: String,
        failureMessage: (_ statusCode: Int, _ body: Data) -> String
    ) async {
        guard var request = baseRequest(url: url, config: config) else { return }

        var body = commonBody(eventName: eventName, deviceID: deviceID)
        if let data, JSONSerialization.isValidJSONObject(data) {
            body["data"] = data
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            DetourLogger.warn(tag, "[Detour:ANALYTICS] Failed to encode \(kind) body.")
            return
        }

        request.httpBody = bodyData

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                DetourLogger.warn(tag, "[Detour:ANALYTICS] \(failureMessage(httpResponse.statusCode, responseData))")
            }
        } catch {
            DetourLogger.warn(tag, "[Detour:ANALYTICS] \(kind) send exception: \(error.localizedDescription)")
        }
    }

    static func refusalMessage(statusCode: Int, body: Data, eventName: String) -> String {
        switch statusCode {
        case 413:
            return "Event \"\(eventName)\" refused: the request body is too large."
        case 429:
            return "Event \"\(eventName)\" refused: rate limit exceeded."
        case 400:
            if let fieldError = try? JSONDecoder().decode(ValidationErrorBody.self, from: body).error?.fieldErrors?.eventName?.first {
                return "Event \"\(eventName)\" refused: \(fieldError)."
            }
        default:
            break
        }
        return "event send failed: \(statusCode)"
    }

    static func sendEvent(config: DetourConfig, eventName: String, data: [String: Any]?, deviceID: String) async {
        await send(
            config: config,
            url: DetourConstants.analyticsEventUrl,
            eventName: eventName,
            deviceID: deviceID,
            data: data,
            kind: "event",
            failureMessage: { statusCode, body in
                refusalMessage(statusCode: statusCode, body: body, eventName: eventName)
            }
        )
    }

    static func sendRetentionEvent(config: DetourConfig, eventName: String, deviceID: String) async {
        await send(
            config: config,
            url: DetourConstants.analyticsRetentionUrl,
            eventName: eventName,
            deviceID: deviceID,
            data: nil,
            kind: "retention event",
            failureMessage: { statusCode, _ in "retention event send failed: \(statusCode)" }
        )
    }
}

// The body of a 400 from the event endpoint. Only `event_name` is read.
struct ValidationErrorBody: Decodable {
    struct ErrorDetails: Decodable {
        let fieldErrors: FieldErrors?
    }

    struct FieldErrors: Decodable {
        let eventName: [String]?

        enum CodingKeys: String, CodingKey {
            case eventName = "event_name"
        }
    }

    let error: ErrorDetails?
}

import Foundation

enum AnalyticsNetwork {
    private static let tag = "AnalyticsApiClient"

    private static func endpoint(of request: AnalyticsRequest) -> DetourEndpoint {
        switch request {
        case .event: return .analyticsEvent
        case .retention: return .analyticsRetention
        case .session: return .analyticsSession
        case .conversion: return .analyticsConversion
        }
    }

    private static func fields(of request: AnalyticsRequest) -> [String: Any] {
        switch request {
        case let .event(name, data, at):
            var fields: [String: Any] = ["event_name": name, "timestamp": ISOTimestamp.string(from: at), "platform": "ios"]
            if let data, JSONSerialization.isValidJSONObject(data) {
                fields["data"] = data
            }
            return fields
        case let .retention(name, at):
            return ["event_name": name, "timestamp": ISOTimestamp.string(from: at), "platform": "ios"]
        case let .session(.start(sessionID, at)):
            return ["type": "start", "session_id": sessionID, "timestamp": ISOTimestamp.string(from: at)]
        case let .session(.end(sessionID, at, duration)):
            return [
                "type": "end",
                "session_id": sessionID,
                "timestamp": ISOTimestamp.string(from: at),
                "duration_ms": Int((duration * 1000).rounded()),
            ]
        case let .conversion(conversion, at):
            var fields: [String: Any] = [
                "name": conversion.name,
                // NSDecimalNumber keeps the exact amount; a Double would turn 0.001234 into 0.0012339999...
                "revenue": NSDecimalNumber(decimal: conversion.revenue),
                "currency": conversion.currency,
                "revenue_type": conversion.revenueType.rawValue,
                "timestamp": ISOTimestamp.string(from: at),
            ]
            fields["product_id"] = conversion.productId
            fields["quantity"] = conversion.quantity
            fields["transaction_id"] = conversion.transactionId
            return fields
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
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                let detail = DetourNetwork.apiErrorMessage(from: data).map { " - \($0)" } ?? ""
                DetourLogger.warn(tag, "[Detour:ANALYTICS] \(endpoint.rawValue) send failed: \(httpResponse.statusCode)\(detail)")
            }
        } catch {
            DetourLogger.warn(tag, "[Detour:ANALYTICS] \(endpoint.rawValue) send exception: \(error.localizedDescription)")
        }
    }
}

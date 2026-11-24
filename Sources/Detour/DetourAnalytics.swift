import Foundation

@MainActor
public final class DetourAnalytics {
    public static let shared = DetourAnalytics()

    private static let tag = "DetourAnalytics"

    private var isMounted = false
    private var subscriptionToken: UUID?
    private var hasLoggedColdStartRetention = false

    private init() {}

    public static func mount(config: DetourConfig) {
        shared.mount(config: config)
    }

    public static func unmount() {
        shared.unmount()
    }

    public static func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    /// Logs an analytics event under a custom name. Custom names must match
    /// `^[a-z0-9_]{1,64}$`. Names starting with `af_` or `dt_`, and
    /// `opened_via_universal_link`, are reserved. An invalid name is dropped
    /// and logged as an error.
    public static func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logRetention(_ eventName: String) {
        shared.logRetention(eventName)
    }

    public func mount(config: DetourConfig) {
        guard !isMounted else { return }
        isMounted = true

        let token = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            guard self != nil else { return }

            Task {
                let deviceID = DeviceIDPersistence.shared.prepareDeviceID()

                if payload.isRetention {
                    await AnalyticsNetwork.sendRetentionEvent(
                        config: config,
                        eventName: payload.eventName,
                        deviceID: deviceID
                    )
                } else {
                    await AnalyticsNetwork.sendEvent(
                        config: config,
                        eventName: payload.eventName,
                        data: payload.data,
                        deviceID: deviceID
                    )
                }
            }
        }

        subscriptionToken = token

        if !hasLoggedColdStartRetention {
            logRetention("app_open")
            hasLoggedColdStartRetention = true
        }
    }

    public func unmount() {
        guard isMounted else { return }
        isMounted = false

        guard let token = subscriptionToken else { return }
        subscriptionToken = nil
        AnalyticsEmitter.shared.unsubscribe(token)
    }

    public func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        logEvent(eventName.rawValue, data: data)
    }

    /// Logs an analytics event under a custom name. Custom names must match
    /// `^[a-z0-9_]{1,64}$`. Names starting with `af_` or `dt_`, and
    /// `opened_via_universal_link`, are reserved. An invalid name is dropped
    /// and logged as an error.
    public func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        if let problem = EventNameRules.problem(eventName) {
            DetourLogger.error(Self.tag, "[Detour:ANALYTICS] Event \"\(eventName)\" dropped: \(problem).")
            return
        }

        #if DEBUG
        if let data {
            warnIfDataTooLarge(eventName: eventName, data: data)
        }
        #endif

        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: data, isRetention: false)
        )
    }

    // Debug-only: it serializes `data` a second time just to measure it.
    private func warnIfDataTooLarge(eventName: String, data: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(data),
              let json = try? JSONSerialization.data(withJSONObject: data),
              json.count > EventNameRules.maxDataBytes
        else { return }

        DetourLogger.warn(
            Self.tag,
            "[Detour:ANALYTICS] Event \"\(eventName)\" has \(json.count) bytes of data as JSON. "
                + "Detour stores at most \(EventNameRules.maxDataBytes) bytes of data per event and may refuse larger events."
        )
    }

    public func logRetention(_ eventName: String) {
        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: nil, isRetention: true)
        )
    }
}

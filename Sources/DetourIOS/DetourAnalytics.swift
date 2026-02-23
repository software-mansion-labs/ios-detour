import Foundation

@MainActor
public final class DetourAnalytics {
    public static let shared = DetourAnalytics()

    private var activeMountCount = 0
    private var mountTokens: Set<UUID> = []
    private var hasLoggedColdStartRetention = false

    private init() {}

    @discardableResult
    public static func mount(config: DetourConfig) -> UUID {
        shared.mount(config: config)
    }

    public static func unmount(_ token: UUID) {
        shared.unmount(token)
    }

    public static func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logRetention(_ eventName: String) {
        shared.logRetention(eventName)
    }

    @discardableResult
    public func mount(config: DetourConfig) -> UUID {
        activeMountCount += 1

        let token = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            guard let self else { return }

            if self.activeMountCount > 1 {
                print("🔗[Detour:ANALYTICS_ERROR] Event \"\(payload.eventName)\" dropped. Multiple analytics mounts (\(self.activeMountCount)) detected. Analytics logging is disabled until only one mount remains.")
                return
            }

            Task {
                let deviceID = await DeviceIDPersistence.shared.prepareDeviceID()

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

        mountTokens.insert(token)

        if !hasLoggedColdStartRetention {
            logRetention("app_open")
            hasLoggedColdStartRetention = true
        }

        return token
    }

    public func unmount(_ token: UUID) {
        guard mountTokens.contains(token) else { return }
        mountTokens.remove(token)
        AnalyticsEmitter.shared.unsubscribe(token)
        activeMountCount = max(0, activeMountCount - 1)
    }

    public func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        logEvent(eventName.rawValue, data: data)
    }

    public func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: data, isRetention: false)
        )
    }

    public func logRetention(_ eventName: String) {
        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: nil, isRetention: true)
        )
    }
}

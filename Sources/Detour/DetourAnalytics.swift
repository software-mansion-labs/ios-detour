import Foundation
import UIKit

@MainActor
public final class DetourAnalytics {
    public static let shared = DetourAnalytics()

    private var isMounted = false
    private var subscriptionToken: UUID?
    private var hasLoggedColdStartRetention = false
    private var revenueWarnings = RevenueWarnings()

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

    public static func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logRetention(_ eventName: String) {
        shared.logRetention(eventName)
    }

    public static func logConversion(_ conversion: DetourConversion) {
        shared.logConversion(conversion)
    }

    public func mount(config: DetourConfig) {
        guard !isMounted else { return }
        isMounted = true

        subscriptionToken = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            guard self != nil else { return }
            Task {
                await AnalyticsNetwork.send(
                    payload,
                    config: config,
                    deviceID: InstallStore.shared.deviceID,
                    userID: UserIdStore.current
                )
            }
        }
        Self.startSessions(config: config)

        if !hasLoggedColdStartRetention {
            logRetention("app_open")
            hasLoggedColdStartRetention = true
        }
    }

    private static func startSessions(config: DetourConfig) {
        SessionManager.shared.start { event in
            Task { @MainActor in
                // The end goes out as the app moves to the background, so ask iOS for time to send it.
                let backgroundTask = BackgroundTask(name: "DetourSession")
                await AnalyticsNetwork.send(
                    .session(event),
                    config: config,
                    deviceID: InstallStore.shared.deviceID,
                    userID: UserIdStore.current
                )
                backgroundTask.end()
            }
        }
    }

    public func unmount() {
        guard isMounted else { return }
        isMounted = false
        SessionManager.shared.stop()

        guard let token = subscriptionToken else { return }
        subscriptionToken = nil
        AnalyticsEmitter.shared.unsubscribe(token)
    }

    public func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        logEvent(eventName.rawValue, data: data)
    }

    public func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        if revenueWarnings.shouldWarn(eventName: eventName, data: data) {
            DetourLogger.warn(
                "DetourAnalytics",
                "[Detour:DEPRECATION] Revenue in logEvent('\(eventName)') is not counted as revenue. Use DetourAnalytics.logConversion instead."
            )
        }
        AnalyticsEmitter.shared.emit(.event(name: eventName, data: data))
    }

    public func logRetention(_ eventName: String) {
        AnalyticsEmitter.shared.emit(.retention(name: eventName))
    }

    public func logConversion(_ conversion: DetourConversion) {
        if let error = conversion.validationError {
            DetourLogger.warn("DetourAnalytics", "[Detour:ANALYTICS] logConversion dropped: \(error)")
            return
        }
        AnalyticsEmitter.shared.emit(.conversion(conversion, at: Date()))
    }
}

/// Warns once per event name per launch, so an event logged often (e.g. `ad_impression`) does not flood the log.
struct RevenueWarnings {
    private var warnedEventNames: Set<String> = []

    mutating func shouldWarn(eventName: String, data: [String: Any]?) -> Bool {
        guard data?["revenue"] != nil else { return false }
        return warnedEventNames.insert(eventName).inserted
    }
}

@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

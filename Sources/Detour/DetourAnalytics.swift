import Foundation
import UIKit

@MainActor
public final class DetourAnalytics {
    public static let shared = DetourAnalytics()

    private var isMounted = false
    private var config: DetourConfig?
    private var subscriptionToken: UUID?
    private var hasLoggedColdStartRetention = false
    private var waitingForConsent: [AnalyticsRequest] = []

    // PROVISIONAL: kept in memory and capped, so a closed gate the app never answers
    // cannot grow without bound. The oldest requests (app_open, the session start) are kept.
    private static let maxWaitingForConsent = 100

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
        self.config = config

        subscriptionToken = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            self?.deliver(payload)
        }
        SessionManager.shared.start { [weak self] event in
            Task { @MainActor in self?.deliver(.session(event)) }
        }

        if !hasLoggedColdStartRetention {
            logRetention("app_open")
            hasLoggedColdStartRetention = true
        }
    }

    public func unmount() {
        guard isMounted else { return }
        isMounted = false
        SessionManager.shared.stop()
        waitingForConsent = []

        guard let token = subscriptionToken else { return }
        subscriptionToken = nil
        AnalyticsEmitter.shared.unsubscribe(token)
    }

    /// Sends the requests that waited for consent once a new consent or config decides them.
    func reevaluateWaiting() {
        let waiting = waitingForConsent
        waitingForConsent = []
        waiting.forEach(deliver)
    }

    private func deliver(_ request: AnalyticsRequest) {
        switch ConsentGate.decision(for: DetourPurpose.analytics) {
        case .send:
            send(request)
        case .wait:
            if waitingForConsent.count < Self.maxWaitingForConsent {
                waitingForConsent.append(request)
            }
        case .drop:
            break
        }
    }

    private func send(_ request: AnalyticsRequest) {
        guard let config else { return }
        // Requests also start as the app moves to the background (a session end, an event logged
        // on exit), so ask iOS for time to finish them.
        let backgroundTask = BackgroundTask(name: "DetourAnalytics")
        Task {
            await AnalyticsNetwork.send(
                request,
                config: config,
                deviceID: InstallStore.shared.deviceID,
                userID: UserIdStore.current
            )
            backgroundTask.end()
        }
    }

    public func logEvent(_ eventName: DetourEventName, data: [String: Any]? = nil) {
        logEvent(eventName.rawValue, data: data)
    }

    public func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        if eventName == DetourEventName.purchase.rawValue, data?["revenue"] != nil {
            DetourLogger.warn(
                "DetourAnalytics",
                "[Detour:DEPRECATION] Revenue in logEvent(.purchase) is deprecated and not counted as revenue. Use logConversion instead."
            )
        }
        AnalyticsEmitter.shared.emit(.event(name: eventName, data: data, at: Date()))
    }

    public func logRetention(_ eventName: String) {
        AnalyticsEmitter.shared.emit(.retention(name: eventName, at: Date()))
    }

    public func logConversion(_ conversion: DetourConversion) {
        AnalyticsEmitter.shared.emit(.conversion(conversion, at: Date()))
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

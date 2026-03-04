import Foundation

typealias AnalyticsListener = (AnalyticsEventPayload) -> Void

@MainActor
final class AnalyticsEmitter {
    static let shared = AnalyticsEmitter()

    private var listeners: [UUID: AnalyticsListener] = [:]

    private init() {}

    func subscribe(_ listener: @escaping AnalyticsListener) -> UUID {
        let token = UUID()
        listeners[token] = listener
        return token
    }

    func unsubscribe(_ token: UUID) {
        listeners[token] = nil
    }

    func emit(_ payload: AnalyticsEventPayload) {
        let snapshot = Array(listeners.values)

        if snapshot.isEmpty {
            print("🔗[Detour:ANALYTICS_WARNING] DetourAnalytics method called but analytics is not mounted. Event dropped.")
            return
        }

        for listener in snapshot {
            listener(payload)
        }
    }
}

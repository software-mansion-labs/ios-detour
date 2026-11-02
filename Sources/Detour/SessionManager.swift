import Foundation
import UIKit

/// Analytics sessions: one `session_id` per continuous use of the app, kept in memory only.
final class SessionManager: @unchecked Sendable {
    static let shared = SessionManager()

    // PROVISIONAL: more than 30 min in the background starts a new session, the threshold Google
    // Analytics and Adjust use, until the API contract settles on an SDK constant or a server value.
    static let backgroundTimeout: TimeInterval = 30 * 60

    enum Event: Equatable {
        case start(sessionID: String, at: Date)
        /// Duration is wall time since the start, so the backend's `start = end - duration`
        /// still holds when the start request was lost.
        case end(sessionID: String, at: Date, duration: TimeInterval)
    }

    private let now: () -> Date
    private let lock = NSLock()
    private var send: ((Event) -> Void)?
    private var sessionID: String?
    private var startedAt: Date?
    private var backgroundedAt: Date?
    private var observers: [NSObjectProtocol] = []

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var currentSessionID: String? {
        lock.lock()
        defer { lock.unlock() }
        return sessionID
    }

    /// Starts a session and follows the app's background and foreground transitions.
    func start(send: @escaping (Event) -> Void) {
        lock.lock()
        guard self.send == nil else {
            lock.unlock()
            return
        }
        self.send = send
        let event = beginSessionLocked()
        lock.unlock()
        send(event)

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appDidEnterBackground()
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appWillEnterForeground()
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        lock.lock()
        send = nil
        sessionID = nil
        startedAt = nil
        backgroundedAt = nil
        lock.unlock()
    }

    // The app can be killed in the background without notice, so every trip to the background
    // reports the end. If the user returns in time, a later end of the same session replaces it.
    func appDidEnterBackground() {
        lock.lock()
        guard let send, let sessionID, let startedAt else {
            lock.unlock()
            return
        }
        let at = now()
        backgroundedAt = at
        lock.unlock()
        send(.end(sessionID: sessionID, at: at, duration: at.timeIntervalSince(startedAt)))
    }

    func appWillEnterForeground() {
        lock.lock()
        guard let send, let backgroundedAt else {
            lock.unlock()
            return
        }
        self.backgroundedAt = nil
        guard now().timeIntervalSince(backgroundedAt) > Self.backgroundTimeout else {
            lock.unlock()
            return
        }
        let event = beginSessionLocked()
        lock.unlock()
        send(event)
    }

    private func beginSessionLocked() -> Event {
        let id = UUID().uuidString.lowercased()
        let at = now()
        sessionID = id
        startedAt = at
        return .start(sessionID: id, at: at)
    }
}

import Foundation

enum UniversalLinkClickOutcome: Equatable {
    case allowed(clickId: String?)
    case denied
    // The request failed, so the click can be sent again.
    case notSaved
}

// Saves one click per link open, even when the SDK gets the same link more than once.
@MainActor
final class UniversalLinkClickRecorder {
    // Matches the server, which also ignores a repeated click on the same link within 10 s.
    static let repeatWindow: TimeInterval = 10

    private var clicks: LinkRegistry<Task<UniversalLinkClickOutcome, Never>>

    init(now: @escaping () -> TimeInterval = MonotonicClock.now) {
        clicks = LinkRegistry(window: Self.repeatWindow, now: now)
    }

    // Calls for the same link within `repeatWindow` make no new request and get the result of the first one.
    func record(config: DetourConfig, url: String) async -> UniversalLinkClickOutcome {
        if let earlier = clicks.get(url) {
            return await earlier.value
        }

        // Stored before the first await, so a second call for this link waits for the same request.
        let request = Task { await DetourNetwork.sendUniversalLinkClick(config: config, url: url) }
        clicks.set(url, request)

        let outcome = await request.value
        if outcome == .notSaved {
            // The next call for this link sends the click again.
            clicks.forget(url, ifStored: request)
        }
        return outcome
    }
}

import Foundation

typealias UniversalLinkClick = (allowed: Bool, clickId: String?)

// Saves one click per link open, even when the SDK gets the same link more than once.
@MainActor
final class UniversalLinkClicks {
    // Matches the server, which also ignores a repeated click on the same link within 10 s.
    static let repeatWindow: TimeInterval = 10
    // Apps keep working when the click cannot be saved. Limits apply only on an explicit deny.
    private static let failOpen: UniversalLinkClick = (allowed: true, clickId: nil)

    private var clicks: LinkRegistry<Task<UniversalLinkClick?, Never>>

    init(now: @escaping () -> TimeInterval = MonotonicClock.now) {
        clicks = LinkRegistry(window: Self.repeatWindow, now: now)
    }

    // Calls for the same link within `repeatWindow` make no new request and get the result of the first one.
    func record(config: DetourConfig, url: String) async -> UniversalLinkClick {
        if let earlier = clicks.get(url) {
            return await earlier.value.value ?? Self.failOpen
        }

        // Stored before the first await, so a second call for this link waits for the same request.
        let request = Task { await DetourNetwork.sendUniversalLinkClick(config: config, url: url) }
        clicks.set(url, request)

        guard let click = await request.value else {
            // The click was not saved, so the next call for this link sends it again.
            clicks.forget(url, ifStored: request)
            return Self.failOpen
        }
        return click
    }
}

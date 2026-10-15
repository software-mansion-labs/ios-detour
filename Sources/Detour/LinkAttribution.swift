import Foundation

// The opening link lives in memory, for this run only; the install link is
// stored for good.
final class LinkAttribution: @unchecked Sendable {
    static let shared = LinkAttribution()

    private static let installClickIDKey = "Detour_installClickId"

    private let lock = NSLock()
    private var openClickID: String?
    private var openType = "organic"

    private init() {}

    func recordDeferredOpen(clickID: String) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(clickID, forKey: Self.installClickIDKey)
        openClickID = clickID
        openType = "deferred"
    }

    func recordLinkOpen(clickID: String) {
        lock.lock()
        defer { lock.unlock() }
        openClickID = clickID
        openType = "verified"
    }

    func recordBlockedLinkOpen() {
        lock.lock()
        defer { lock.unlock() }
        openClickID = nil
        openType = "verified"
    }

    // Custom schemes also carry OAuth returns, so they never replace a Detour link.
    func recordSchemeOpen() {
        lock.lock()
        defer { lock.unlock() }
        if openClickID == nil {
            openType = "scheme"
        }
    }

    var payload: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "install_click_id": UserDefaults.standard.string(forKey: Self.installClickIDKey) ?? NSNull(),
            "open_click_id": openClickID ?? NSNull(),
            "open_type": openType,
        ]
    }
}

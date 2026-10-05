import Foundation

// In memory on purpose: a cold start without a link starts unattributed.
final class SessionAttribution: @unchecked Sendable {
    static let shared = SessionAttribution()

    private let lock = NSLock()
    private var clickID: String?

    private init() {}

    var currentClickID: String? {
        lock.lock()
        defer { lock.unlock() }
        return clickID
    }

    func setClickID(_ clickID: String) {
        lock.lock()
        defer { lock.unlock() }
        self.clickID = clickID
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        clickID = nil
    }
}

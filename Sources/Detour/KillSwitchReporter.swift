import Foundation

/// Reports the kill switch state to the server until it is confirmed (API contract, kill switch).
/// One request at a time, each given up to 60 s, so an older state never lands after a newer
/// one: the server keeps the state that arrived last. An unconfirmed state is sent again on the
/// next launch, because a lost "off" would leave the install in ad network postbacks.
@MainActor
final class KillSwitchReporter {
    enum Outcome {
        case confirmed
        case retry
        /// The server rejected the request; retrying in this launch will not change that.
        case stop
    }

    typealias Send = (_ enabled: Bool, _ at: Date) async -> Outcome

    static let firstRetryDelay: TimeInterval = 5
    static let maxRetryDelay: TimeInterval = 300

    private let store: InstallStore
    private let send: Send
    private let sleep: (TimeInterval) async -> Void
    private var isRunning = false

    init(
        store: InstallStore,
        send: @escaping Send,
        sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.store = store
        self.send = send
        self.sleep = sleep
    }

    func sync() {
        guard !isRunning else { return }
        isRunning = true
        Task { await run() }
    }

    func run() async {
        defer { isRunning = false }
        var retryDelay = Self.firstRetryDelay
        while let state = store.unreportedKillSwitch {
            switch await send(state.enabled, state.at) {
            case .confirmed:
                // A change made while the request was out is still unreported, so the loop sends it next.
                store.markKillSwitchReported(enabled: state.enabled)
                retryDelay = Self.firstRetryDelay
            case .retry:
                await sleep(retryDelay)
                retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
            case .stop:
                return
            }
        }
    }
}

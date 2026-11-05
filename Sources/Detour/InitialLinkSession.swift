import Foundation

enum LaunchSource {
    // Without scenes, iOS passes the launch link once more to open url or continueUserActivity.
    // The SDK delivers it there only, so the app does not get it twice.
    case launchOptions
    // A scene gets its launch link only here, not in scene(_:continue:) or scene(_:openURLContexts:).
    case connectionOptions
}

struct LaunchContext {
    let url: URL?
    let waitsForContinueCallback: Bool
    let source: LaunchSource
}

extension LaunchContext {
    init(candidateURLs: [URL?], hasBrowsingActivity: Bool, source: LaunchSource) {
        let url = candidateURLs.compactMap { $0 }.first { !LinkUtils.isInfrastructureUrl($0.absoluteString) }
        self.init(url: url, waitsForContinueCallback: url == nil && hasBrowsingActivity, source: source)
    }
}

enum InitialLinkAction: Equatable {
    case open(URL)
    case awaitCallback
    case resolveDeferred
    case skip
}

enum DeferredMatchOutcome: Equatable {
    case kept
    // A link opened while the match ran. The app follows that link, so it must not get the deferred link too.
    case replaced
}

// Decides what each resolveInitialLink call does.
struct InitialLinkSession {
    private var isHandled = false
    // A reset keeps running matches: each one still hands its result to the completion that started it.
    private var deferredMatches: [Int: DeferredMatchOutcome] = [:]
    private var lastDeferredMatchID = 0

    mutating func reset() {
        isHandled = false
    }

    mutating func action(for launch: LaunchContext, mode: LinkProcessingMode) -> InitialLinkAction {
        let url = launch.url.flatMap { mode.handles(LinkUtils.detectLinkType(from: $0)) ? $0 : nil }

        guard !isHandled else {
            // A scene app gets its launch link only in connectionOptions, so an app delegate call before it finds none.
            // A later scene, such as a new iPad window or a scene that iOS reconnects after discarding it, also
            // gets its link only there. Both open like a callback link, without deferred matching.
            guard launch.source == .connectionOptions, let url else { return .skip }
            // processLink marks it too, but only in a later task. A deferred match that finishes first would still
            // hand over its link.
            linkOpened()
            return .open(url)
        }

        isHandled = true
        if let url {
            return launch.source == .launchOptions ? .awaitCallback : .open(url)
        }
        if launch.waitsForContinueCallback, mode.handles(.verified) {
            return .awaitCallback
        }
        return .resolveDeferred
    }

    mutating func startDeferredMatch() -> Int {
        lastDeferredMatchID += 1
        deferredMatches[lastDeferredMatchID] = .kept
        return lastDeferredMatchID
    }

    mutating func linkOpened() {
        deferredMatches = deferredMatches.mapValues { _ in .replaced }
    }

    mutating func finishDeferredMatch(_ id: Int) -> DeferredMatchOutcome {
        deferredMatches.removeValue(forKey: id) ?? .kept
    }
}

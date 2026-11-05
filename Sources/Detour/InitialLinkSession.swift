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

// Decides what each resolveInitialLink call does.
struct InitialLinkSession {
    private enum DeferredMatch {
        case notRunning
        case running
        // A link opened while the match ran. The app follows that link, so it must not get the deferred link too.
        case replaced
    }

    private var isHandled = false
    private var deferredMatch = DeferredMatch.notRunning

    var isDeferredLinkReplaced: Bool {
        deferredMatch == .replaced
    }

    mutating func reset() {
        isHandled = false
        deferredMatch = .notRunning
    }

    mutating func action(for launch: LaunchContext, mode: LinkProcessingMode) -> InitialLinkAction {
        let url = launch.url.flatMap { mode.handles(LinkUtils.detectLinkType(from: $0)) ? $0 : nil }

        guard !isHandled else {
            // A scene app gets its launch link only in connectionOptions, so an app delegate call before it finds none.
            // A later scene, such as a new iPad window or a scene that iOS reconnects after discarding it, also
            // gets its link only there. Both open like a callback link, without deferred matching.
            guard launch.source == .connectionOptions, let url else { return .skip }
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

    mutating func startDeferredMatch() {
        deferredMatch = .running
    }

    mutating func linkOpened() {
        if deferredMatch == .running {
            deferredMatch = .replaced
        }
    }

    mutating func finishDeferredMatch() {
        deferredMatch = .notRunning
    }
}

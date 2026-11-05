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
    private enum State {
        case notHandled
        // A scene app gets its launch link only in connectionOptions, so the app delegate finds none.
        // The first scene call can still open that link in place of the deferred link.
        case handledWithoutLaunchLink
        case handled
        case deferredLinkReplacedByScene
    }

    private var state = State.notHandled

    var isDeferredLinkReplaced: Bool {
        state == .deferredLinkReplacedByScene
    }

    mutating func reset() {
        state = .notHandled
    }

    mutating func action(for launch: LaunchContext, mode: LinkProcessingMode) -> InitialLinkAction {
        let url = launch.url.flatMap { mode.handles(LinkUtils.detectLinkType(from: $0)) ? $0 : nil }

        switch state {
        case .notHandled:
            if let url {
                state = .handled
                return launch.source == .launchOptions ? .awaitCallback : .open(url)
            }
            if launch.waitsForContinueCallback, mode.handles(.verified) {
                state = .handled
                return .awaitCallback
            }
            state = launch.source == .launchOptions ? .handledWithoutLaunchLink : .handled
            return .resolveDeferred
        case .handledWithoutLaunchLink:
            guard launch.source == .connectionOptions else { return .skip }
            guard let url else {
                state = .handled
                return .skip
            }
            state = .deferredLinkReplacedByScene
            return .open(url)
        case .handled, .deferredLinkReplacedByScene:
            // A later scene, such as a new iPad window or a scene that iOS reconnects after discarding it,
            // gets its link only in connectionOptions. It opens like a callback link, without deferred matching.
            guard launch.source == .connectionOptions, let url else { return .skip }
            return .open(url)
        }
    }
}

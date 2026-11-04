import Foundation

enum LaunchSource {
    // Without scenes, iOS passes the launch link once more to open url or continueUserActivity.
    case launchOptions
    // A scene gets its launch link only here, not in scene(_:continue:) or scene(_:openURLContexts:).
    case connectionOptions

    var isRedelivered: Bool {
        self == .launchOptions
    }
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
    case awaitContinueCallback
    case resolveDeferred
    case skip
}

// Decides what each resolveInitialLink call of one launch does.
struct InitialLinkSession {
    private enum State {
        case notHandled
        // A scene app gets its launch link only in connectionOptions, so the app delegate finds none.
        // The scene call can still open that link.
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
                return .open(url)
            }
            if launch.waitsForContinueCallback, mode.handles(.verified) {
                state = .handled
                return .awaitContinueCallback
            }
            state = launch.source == .launchOptions ? .handledWithoutLaunchLink : .handled
            return .resolveDeferred
        case .handledWithoutLaunchLink:
            guard launch.source == .connectionOptions, let url else { return .skip }
            state = .deferredLinkReplacedByScene
            return .open(url)
        case .handled, .deferredLinkReplacedByScene:
            return .skip
        }
    }
}

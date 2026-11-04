import Foundation

// One tap can reach the SDK more than once. Every call gets the link, and the later ones are marked as repeats.
struct LinkOpens {
    // Without scenes, iOS passes the cold-start link in the launch options and then once more to
    // continueUserActivity or open url, after didFinishLaunching returns. A slow launch takes seconds.
    static let redeliveryWindow: TimeInterval = 10
    // A repeat this soon is the same tap delivered twice, for example by two forwarding delegates.
    // A later one is the user opening the link again.
    static let sameTapWindow: TimeInterval = 1

    private enum Open {
        case awaitingRedelivery
        case delivered
    }

    private var opens: LinkRegistry<Open>

    init(now: @escaping () -> TimeInterval = MonotonicClock.now) {
        opens = LinkRegistry(window: Self.redeliveryWindow, now: now)
    }

    // False when an app callback delivered this link first.
    mutating func claimLaunchLink(_ url: String, source: LaunchSource) -> Bool {
        if opens.get(url) != nil {
            return false
        }
        opens.set(url, source.isRedelivered ? .awaitingRedelivery : .delivered)
        return true
    }

    // A real second tap needs the user to leave the app first, and iOS redelivers the launch link before that.
    // So after the app leaves the foreground, that tap must not be marked as a repeat.
    mutating func stopAwaitingRedelivery() {
        opens.removeAll { $0 == .awaitingRedelivery }
    }

    mutating func claimCallbackLink(_ url: String) -> Bool {
        if let earlier = opens.get(url) {
            switch earlier.stored {
            case .awaitingRedelivery:
                // iOS sends the launch link once more. Let the next tap on it through.
                opens.set(url, .delivered)
                return false
            case .delivered where earlier.age < Self.sameTapWindow:
                return false
            case .delivered:
                break
            }
        }
        opens.set(url, .delivered)
        return true
    }
}

import Foundation

// PROVISIONAL: the names until the React Native and Android SDKs ship the same status.
/// What the SDK does now, for debugging a consent integration. From `Detour.shared.getStatus()`.
public struct DetourStatus: Equatable, Sendable {
    /// What happens now to a request for a purpose.
    public enum Decision: String, Sendable {
        /// Sent.
        case send
        /// Kept until consent decides it.
        case wait
        /// Dropped.
        case drop

        init(_ decision: GateDecision) {
            switch decision {
            case .send: self = .send
            case .wait: self = .wait
            case .drop: self = .drop
            }
        }
    }

    /// `start()` was called, or `configure` called it.
    public let isStarted: Bool
    /// `false` after `setEnabled(false)`.
    public let isEnabled: Bool
    /// `setConsent` was called on this launch.
    public let hasConsentThisLaunch: Bool
    /// Purpose ID → its decision now.
    public let purposes: [String: Decision]
}

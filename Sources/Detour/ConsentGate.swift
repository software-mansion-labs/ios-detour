import Foundation

/// The consent the app passed: on this launch in memory, and the last one across launches.
/// Holds no identifier.
enum ConsentStore {
    private static let key = "Detour_consent"
    private static let lock = NSLock()
    private static var consentPassedThisLaunch: DetourConsent?

    /// Also the `consent_snapshot` of every request. A stored consent is not sent: it is not
    /// trusted to grant anything until the app passes it again.
    static var passedThisLaunch: DetourConsent? {
        lock.lock()
        defer { lock.unlock() }
        return consentPassedThisLaunch
    }

    static var stored: DetourConsent? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(DetourConsent.self, from: $0) }
    }

    static func record(_ consent: DetourConsent) {
        lock.lock()
        consentPassedThisLaunch = consent
        lock.unlock()
        if let data = try? JSONEncoder().encode(consent) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum GateDecision: Equatable {
    case send
    /// Kept until the app passes a consent that decides it.
    case wait
    case drop
}

/// Decides whether a request for a purpose may leave the device: the kill switch first, then consent.
enum ConsentGate {
    @MainActor
    static func decision(for purpose: String) -> GateDecision {
        decision(
            for: purpose,
            isEnabled: InstallStore.shared.isEnabled,
            consentPassedThisLaunch: ConsentStore.passedThisLaunch,
            storedConsent: ConsentStore.stored,
            gateDefault: SdkConfigStore.shared.current.gateDefault(for: purpose)
        )
    }

    // PROVISIONAL: the stricter cold start rule until the legal answer. A consent stored on an
    // earlier launch can only block: the user may have withdrawn it in the consent platform since,
    // so a grant counts only once the app passes it again on this launch.
    static func decision(
        for purpose: String,
        isEnabled: Bool,
        consentPassedThisLaunch: DetourConsent?,
        storedConsent: DetourConsent?,
        gateDefault: ConsentGateDefault
    ) -> GateDecision {
        guard isEnabled else { return .drop }
        if let consent = consentPassedThisLaunch {
            return consent.purposes[purpose] == true ? .send : .drop
        }
        if let storedConsent, storedConsent.purposes[purpose] != true {
            return .drop
        }
        return gateDefault == .open ? .send : .wait
    }
}

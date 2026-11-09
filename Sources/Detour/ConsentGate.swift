import Foundation

/// The consent the app passed: on this launch in memory, and the last one across launches.
/// Holds no identifier.
enum ConsentStore {
    private static let key = "Detour_consent"
    // Holds the device ID the server confirmed the consent for. UserDefaults come back from a
    // backup but the device ID does not, so a restored install must send the consent again.
    private static let confirmedKey = "Detour_consent_confirmed"
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

    /// Records the consent and returns it with its timestamp filled in, or nil when the server
    /// already has this choice.
    static func record(_ consent: DetourConsent, deviceID: String, now: Date = Date()) -> DetourConsent? {
        let (resolved, needsSend) = prepare(
            consent,
            stored: stored,
            confirmedDeviceID: UserDefaults.standard.string(forKey: confirmedKey),
            deviceID: deviceID,
            now: now
        )
        lock.lock()
        consentPassedThisLaunch = resolved
        lock.unlock()
        guard needsSend else { return nil }
        if let data = try? JSONEncoder().encode(resolved) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: confirmedKey)
        return resolved
    }

    /// Called after a 2xx, so the same choice is not sent again on later launches.
    static func markConfirmed(_ consent: DetourConsent, deviceID: String) {
        guard isStill(consent, stored: stored) else { return }
        UserDefaults.standard.set(deviceID, forKey: confirmedKey)
    }

    // A newer choice recorded while this one was in flight still needs its own send. Compared
    // as sent, because the stored timestamp keeps only milliseconds.
    static func isStill(_ sent: DetourConsent, stored: DetourConsent?) -> Bool {
        guard let stored, stored.isSameChoice(as: sent) else { return false }
        return stored.timestamp.map(ISOTimestamp.string(from:)) == sent.timestamp.map(ISOTimestamp.string(from:))
    }

    // Apps pass the consent on every launch. Sending each one as new would store a new choice
    // on the server every launch, dated "now".
    static func prepare(
        _ consent: DetourConsent,
        stored: DetourConsent?,
        confirmedDeviceID: String?,
        deviceID: String,
        now: Date
    ) -> (consent: DetourConsent, needsSend: Bool) {
        guard consent.timestamp == nil else { return (consent, true) }
        var resolved = consent
        if let stored, stored.isSameChoice(as: consent) {
            resolved.timestamp = stored.timestamp
            return (resolved, confirmedDeviceID != deviceID)
        }
        // PROVISIONAL: the time the app passed the choice, not the time the request left, so a
        // choice queued until `configure` keeps the earlier time.
        resolved.timestamp = now
        return (resolved, true)
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

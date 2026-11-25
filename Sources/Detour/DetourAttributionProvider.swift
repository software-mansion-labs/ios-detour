import Foundation

/// Implemented by `DetourAttribution`; pass it to `Detour.shared.configure(_:attribution:)`.
/// The core SDK knows only this protocol, so it links no attribution framework.
public protocol DetourAttributionProvider: AnyObject, Sendable {
    /// Called once, when the SDK starts.
    @MainActor func didStart(_ host: DetourAttributionHost)
    /// Called with each valid conversion while consent to `DetourPurpose.attribution` lets requests through.
    @MainActor func didLogConversion(_ conversion: DetourConversion)
    /// The Apple Search Ads token for deferred link matching, or `nil` when there is none.
    func attributionToken() async -> String?
    /// The IDFA, or `nil` when the user did not allow tracking. The SDK sends it only with consent
    /// to `DetourPurpose.adNetworkSharing`.
    func advertisingID() -> String?
}

extension DetourAttributionProvider {
    public func advertisingID() -> String? { nil }
}

/// A response to a GET that sends the last `ETag` as `If-None-Match`.
public enum DetourFetchResult: Sendable {
    case updated(body: Data, etag: String?)
    case notModified
    case failed
}

/// What the core SDK lends the attribution product: the consent gate and the Detour API.
@MainActor
public final class DetourAttributionHost {
    private let config: DetourConfig

    init(config: DetourConfig) {
        self.config = config
    }

    // PROVISIONAL: SKAdNetwork and AdAttributionKit wait for consent to attribution, like requests
    // sent with attribution on.
    /// True while consent to `DetourPurpose.attribution` passed on this launch lets requests through.
    public var isAttributionAllowed: Bool {
        ConsentGate.decision(for: DetourPurpose.attribution) == .send
    }

    /// Changes when the storage came back from a backup of another install.
    public var installID: String {
        InstallStore.shared.deviceID
    }

    /// Writes a warning to the Detour log.
    public nonisolated static func logWarning(_ message: String) {
        DetourLogger.warn("DetourAttribution", message)
    }

    public func fetchConversionValueSchema(etag: String?) async -> DetourFetchResult {
        // The kill switch stops every request but sdk/disable; the cached schema stays.
        guard InstallStore.shared.isEnabled else { return .failed }
        return await SdkNetwork.fetchConversionValueSchema(config: config, sdkPackage: AttributionMode.sdkPackage, etag: etag)
    }
}

/// The `X-SDK-Package` header value.
enum SdkPackage: String {
    case core
    case mmp
}

/// Attribution mode: on once the app passes a provider to `configure`.
@MainActor
enum AttributionMode {
    // PROVISIONAL: the same cap as events waiting for consent, so an app that never passes the
    // choice cannot grow the queue without bound.
    private static let maxWaitingConversions = 100

    private(set) static var provider: DetourAttributionProvider?
    private static var isStarted = false
    private static var hasProviderStarted = false
    private static var waitingForDecision: [() -> Void] = []
    private static var waitingConversions: [DetourConversion] = []

    static func register(_ provider: DetourAttributionProvider?) {
        self.provider = provider
        isStarted = false
        hasProviderStarted = false
        waitingForDecision = []
        waitingConversions = []
    }

    /// True while attribution is on and its gate waits for consent.
    static var isWaitingForConsent: Bool {
        provider != nil && ConsentGate.decision(for: DetourPurpose.attribution) == .wait
    }

    // The backend never attributes an install whose first match went as `core`, so with
    // attribution on that match waits until the gate decides: `mmp` after a grant, `core` after a refusal.
    /// Runs `work` once the attribution gate stops waiting.
    static func whenDecided(_ work: @escaping () -> Void) {
        whenDecided(isWaiting: isWaitingForConsent, work)
    }

    static func whenDecided(isWaiting: Bool, _ work: @escaping () -> Void) {
        if isWaiting {
            waitingForDecision.append(work)
        } else {
            work()
        }
    }

    /// Called after a consent, config or kill switch change.
    static func reevaluate() {
        reevaluate(isWaiting: isWaitingForConsent)
    }

    static func reevaluate(isWaiting: Bool) {
        flushConversions()
        guard !isWaiting else { return }
        let waiting = waitingForDecision
        waitingForDecision = []
        waiting.forEach { $0() }
    }

    // `Detour.start()` runs again when analytics are mounted again; the provider starts once.
    // It starts after the gate decides, so a consent passed after `start()` still registers the
    // install for SKAdNetwork on this launch.
    static func start(config: DetourConfig) {
        guard !isStarted, let provider else { return }
        isStarted = true
        whenDecided {
            guard self.provider === provider else { return }
            provider.didStart(DetourAttributionHost(config: config))
            hasProviderStarted = true
            flushConversions()
        }
    }

    /// The package of a request that starts now.
    static var sdkPackage: SdkPackage {
        sdkPackage(hasProvider: provider != nil, decision: ConsentGate.decision(for: DetourPurpose.attribution))
    }

    // The backend attributes every `mmp` request, so a request goes as `core` until the attribution
    // gate lets it through. It never waits for consent: a deep link must not be held back.
    static func sdkPackage(hasProvider: Bool, decision: GateDecision) -> SdkPackage {
        hasProvider && decision == .send ? .mmp : .core
    }

    // PROVISIONAL: the deferred link waits at most 1 s for the token, then goes without it.
    /// The provider's Apple Search Ads token for a request of this package, or `nil` for `core`,
    /// without a provider, or with no token in time.
    static func attributionToken(for sdkPackage: SdkPackage, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> String? {
        guard sdkPackage == .mmp, let provider else { return nil }
        // A task group would still wait for a slow provider after the timeout, so the first
        // answer resumes the caller and the later one is dropped.
        return await withCheckedContinuation { continuation in
            let first = FirstAnswer(continuation)
            Task { first.resume(await provider.attributionToken()) }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                first.resume(nil)
            }
        }
    }

    /// The identifiers for a request of this package: none for `core` or without a provider.
    static func deviceIdentifiers(for sdkPackage: SdkPackage) -> DeviceIdentifiers {
        deviceIdentifiers(for: sdkPackage, adNetworkSharing: ConsentGate.decision(for: DetourPurpose.adNetworkSharing))
    }

    // The advertising ID is only for postbacks to ad networks, so it needs that purpose, not attribution.
    static func deviceIdentifiers(for sdkPackage: SdkPackage, adNetworkSharing: GateDecision) -> DeviceIdentifiers {
        guard sdkPackage == .mmp, let provider else { return .none }
        var identifiers = DeviceIdentifiers.none
        if adNetworkSharing == .send {
            identifiers.advertisingID = provider.advertisingID().map(AdvertisingID.idfa)
        }
        return identifiers
    }

    // A conversion logged before `start()` or while the gate waits is kept until the provider starts,
    // so a purchase made before the consent prompt is answered still counts for SKAdNetwork.
    static func forwardConversion(_ conversion: DetourConversion) {
        guard provider != nil, waitingConversions.count < maxWaitingConversions else { return }
        waitingConversions.append(conversion)
        flushConversions()
    }

    private static func flushConversions() {
        flushConversions(decision: ConsentGate.decision(for: DetourPurpose.attribution))
    }

    static func flushConversions(decision: GateDecision) {
        guard hasProviderStarted, let provider, decision != .wait else { return }
        let waiting = waitingConversions
        waitingConversions = []
        if decision == .send {
            waiting.forEach { provider.didLogConversion($0) }
        }
    }
}

/// Resumes a continuation once, with whichever answer comes first.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

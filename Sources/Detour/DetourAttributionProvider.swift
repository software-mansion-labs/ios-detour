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

    // PROVISIONAL: SKAdNetwork and AdAttributionKit wait for consent to attribution, like the `mmp`
    // package, until the legal answer on whether those APIs need it.
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
    private(set) static var provider: DetourAttributionProvider?
    private static var isStarted = false

    static func register(_ provider: DetourAttributionProvider?) {
        self.provider = provider
        isStarted = false
    }

    // `Detour.start()` runs again when analytics are mounted again; the provider starts once.
    static func start(config: DetourConfig) {
        guard !isStarted, let provider else { return }
        isStarted = true
        provider.didStart(DetourAttributionHost(config: config))
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

    static func forwardConversion(_ conversion: DetourConversion) {
        forwardConversion(conversion, decision: ConsentGate.decision(for: DetourPurpose.attribution))
    }

    static func forwardConversion(_ conversion: DetourConversion, decision: GateDecision) {
        guard decision == .send else { return }
        provider?.didLogConversion(conversion)
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

import Foundation

/// Implemented by `DetourAttribution`; pass it to `Detour.shared.configure(_:attribution:)`.
/// The core SDK knows only this protocol, so it links no attribution framework.
public protocol DetourAttributionProvider: AnyObject, Sendable {
    /// Called with each valid conversion while consent to `DetourPurpose.attribution` lets requests through.
    @MainActor func didLogConversion(_ conversion: DetourConversion)
    /// The Apple Search Ads token for deferred link matching, or `nil` when there is none.
    func attributionToken() async -> String?
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

    static func register(_ provider: DetourAttributionProvider?) {
        self.provider = provider
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

    // PROVISIONAL: a conversion feeds the SKAdNetwork and AdAttributionKit value only with consent
    // to attribution, until the legal answer on whether those APIs need it.
    static func forwardConversion(_ conversion: DetourConversion) {
        forwardConversion(conversion, decision: ConsentGate.decision(for: DetourPurpose.attribution))
    }

    static func forwardConversion(_ conversion: DetourConversion, decision: GateDecision) {
        guard decision == .send else { return }
        provider?.didLogConversion(conversion)
    }
}

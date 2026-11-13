import Detour
import Foundation

/// Turns on attribution: `Detour.shared.configure(config, attribution: DetourAttribution())`.
/// Requests feed attribution only with consent to `DetourPurpose.attribution` passed on this
/// launch. The install is attributed from deferred matching, so configure with `autoStart: false`
/// and call `start()` after `setConsent`.
public final class DetourAttribution: DetourAttributionProvider {
    public init() {}

    @MainActor public func didLogConversion(_ conversion: DetourConversion) {}

    public func attributionToken() async -> String? {
        nil
    }
}

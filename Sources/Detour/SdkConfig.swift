import Foundation

enum ConsentGateDefault: String {
    /// Sends while the app has not passed a consent decision.
    case open
    /// Waits for `setConsent`.
    case closed
}

/// The per-app values from `GET /api/sdk/config` that the SDK uses.
struct SdkConfig: Equatable {
    let schemaVersion: Int
    let consentGateDefaults: [String: ConsentGateDefault]

    // The only gate values written in the SDK, used before the first successful fetch
    // (API contract, consent gate fallback). Every other value comes from the server.
    static let fallback = SdkConfig(
        schemaVersion: 1,
        consentGateDefaults: [DetourPurpose.analytics: .open]
    )

    /// A purpose the config does not list waits for consent.
    func gateDefault(for purpose: String) -> ConsentGateDefault {
        consentGateDefaults[purpose] ?? .closed
    }

    private struct Response: Decodable {
        let schema_version: Int
        let consent_gate_default: [String: String]
    }

    /// nil for a body in another shape, so an unexpected response never replaces a good config.
    init?(json: Data) {
        guard let response = try? JSONDecoder().decode(Response.self, from: json) else { return nil }
        schemaVersion = response.schema_version
        consentGateDefaults = response.consent_gate_default.compactMapValues(ConsentGateDefault.init(rawValue:))
    }

    init(schemaVersion: Int, consentGateDefaults: [String: ConsentGateDefault]) {
        self.schemaVersion = schemaVersion
        self.consentGateDefaults = consentGateDefaults
    }
}

/// The last config the server sent, kept across launches and used while a fetch fails.
@MainActor
final class SdkConfigStore {
    static let shared = SdkConfigStore()

    typealias FetchResult = DetourFetchResult

    private struct Cached: Codable {
        let appID: String
        let etag: String?
        let body: Data
    }

    private static let key = "Detour_sdkConfig"

    private let defaults: UserDefaults
    private var cached: Cached?
    private var loaded = SdkConfig.fallback
    private var hasFetchEnded = false

    // On a first launch nothing is cached, and the fallback opens analytics. Until the first
    // fetch ends, every gate is closed instead, so an app the server keeps closed sends nothing
    // before consent.
    private static let untilFirstFetch = SdkConfig(schemaVersion: SdkConfig.fallback.schemaVersion, consentGateDefaults: [:])

    /// False on a first launch until the first `sdk/config` fetch ends.
    var isKnown: Bool { cached != nil || hasFetchEnded }

    var current: SdkConfig { isKnown ? loaded : Self.untilFirstFetch }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads the config cached for this app. A cache from another app ID is ignored.
    func load(appID: String) {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode(Cached.self, from: data),
              saved.appID == appID,
              let config = SdkConfig(json: saved.body)
        else { return }
        cached = saved
        loaded = config
    }

    var etag: String? { cached?.etag }

    /// Ends the first fetch whatever its result. Returns true when the config changed.
    @discardableResult
    func apply(_ result: FetchResult, appID: String) -> Bool {
        hasFetchEnded = true
        guard case let .updated(body, etag) = result, let config = SdkConfig(json: body) else { return false }

        let saved = Cached(appID: appID, etag: etag, body: body)
        cached = saved
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.key)
        }
        let changed = config != loaded
        loaded = config
        return changed
    }
}

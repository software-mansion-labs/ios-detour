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
        consentGateDefaults: ["analytics": .open]
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

    enum FetchResult {
        case updated(body: Data, etag: String?)
        case notModified
        case failed
    }

    private struct Cached: Codable {
        let appID: String
        let etag: String?
        let body: Data
    }

    private static let key = "Detour_sdkConfig"

    private let defaults: UserDefaults
    private var cached: Cached?
    private(set) var current = SdkConfig.fallback

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
        current = config
    }

    var etag: String? { cached?.etag }

    /// Returns true when the config changed.
    @discardableResult
    func apply(_ result: FetchResult, appID: String) -> Bool {
        guard case let .updated(body, etag) = result, let config = SdkConfig(json: body) else { return false }

        let saved = Cached(appID: appID, etag: etag, body: body)
        cached = saved
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.key)
        }
        let changed = config != current
        current = config
        return changed
    }
}

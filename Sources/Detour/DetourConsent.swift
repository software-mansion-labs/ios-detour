import Foundation

/// Purpose IDs for `DetourConsent.purposes`. Strings, not an enum, so a purpose added on the
/// Detour server can be passed before the SDK knows it.
public enum DetourPurpose {
    /// Events, sessions and conversions stored for your statistics.
    public static let analytics = "analytics"
    /// Assigning an install to a campaign.
    public static let attribution = "attribution"
    /// Sending install and conversion data to ad networks.
    public static let adNetworkSharing = "ad_network_sharing"
    /// Ad personalization, for example Google's `ad_personalization`.
    public static let adPersonalization = "ad_personalization"
}

/// The user's choice from your consent platform, passed with `Detour.shared.setConsent`.
public struct DetourConsent: Sendable, Equatable {
    /// Purpose ID → granted. A purpose missing from the map is not granted.
    public var purposes: [String: Bool]
    /// When the user made the choice.
    public var timestamp: Date
    /// The version of the consent text the user saw, for example the consent platform's version.
    public var consentTextRef: String?
    /// Version of the purpose list. `nil` uses the version from the Detour server.
    public var schemaVersion: Int?
    /// The user's legal regime, for example `eea`.
    public var region: String?
    /// Where the choice came from, for example `cmp`.
    public var source: String?

    public init(
        purposes: [String: Bool],
        timestamp: Date = Date(),
        consentTextRef: String? = nil,
        schemaVersion: Int? = nil,
        region: String? = nil,
        source: String? = nil
    ) {
        self.purposes = purposes
        self.timestamp = timestamp
        self.consentTextRef = consentTextRef
        self.schemaVersion = schemaVersion
        self.region = region
        self.source = source
    }
}

// The wire format of the API contract, also used to store the consent on the device.
extension DetourConsent: Codable {
    private enum CodingKeys: String, CodingKey {
        case purposes, timestamp, region, source
        case consentTextRef = "consent_text_ref"
        case schemaVersion = "schema_version"
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(String.self, forKey: .timestamp)
        guard let date = Self.timestampFormatter.date(from: timestamp) else {
            throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Not an ISO 8601 timestamp")
        }
        self.init(
            purposes: try container.decode([String: Bool].self, forKey: .purposes),
            timestamp: date,
            consentTextRef: try container.decodeIfPresent(String.self, forKey: .consentTextRef),
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion),
            region: try container.decodeIfPresent(String.self, forKey: .region),
            source: try container.decodeIfPresent(String.self, forKey: .source)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purposes, forKey: .purposes)
        try container.encode(Self.timestampFormatter.string(from: timestamp), forKey: .timestamp)
        try container.encodeIfPresent(consentTextRef, forKey: .consentTextRef)
        try container.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(source, forKey: .source)
    }
}

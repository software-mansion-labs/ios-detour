import Foundation

public struct DetourConfig: Sendable {
    public let apiKey: String
    public let appID: String
    public let shouldUseClipboard: Bool
    public let linkProcessingMode: LinkProcessingMode
    /// Detour API host for tests and non-production environments. `nil` uses the production Detour API.
    public let baseURL: URL?
    /// Called on `Detour.shared.setUserId`; returning `false` drops the value. Use it to reject values
    /// that must not leave the device, such as e-mail addresses or phone numbers.
    public let userIdValidator: (@Sendable (String) -> Bool)?

    public init(
        apiKey: String,
        appID: String,
        shouldUseClipboard: Bool = true,
        linkProcessingMode: LinkProcessingMode = .all,
        baseURL: URL? = nil,
        userIdValidator: (@Sendable (String) -> Bool)? = nil
    ) {
        self.apiKey = apiKey
        self.appID = appID
        self.shouldUseClipboard = shouldUseClipboard
        self.linkProcessingMode = linkProcessingMode
        self.baseURL = baseURL
        self.userIdValidator = userIdValidator
    }
}

public enum LinkProcessingMode: String, Sendable {
    case all
    case webOnly = "web-only"
    case deferredOnly = "deferred-only"
}

public enum LinkType: String, Codable, Sendable {
    case deferred
    case verified
    case scheme
}

public struct DetourLink: Sendable {
    public let url: String
    public let route: String
    public let pathname: String
    public let params: [String: String]
    public let type: LinkType

    public init(
        url: String,
        route: String,
        pathname: String,
        params: [String: String],
        type: LinkType
    ) {
        self.url = url
        self.route = route
        self.pathname = pathname
        self.params = params
        self.type = type
    }
}

struct SignalMatchRequest: Codable {
    let platform: String
    let model: String
    let manufacturer: String
    let systemVersion: String
    let screenWidth: Double
    let screenHeight: Double
    let scale: Double
    let locale: [LocaleTag]
    let timezone: String
    let userAgent: String
    let timestamp: Int64
    let pastedLink: String?
    let deviceID: String
    let userID: String?

    enum CodingKeys: String, CodingKey {
        case platform, model, manufacturer, systemVersion, screenWidth, screenHeight, scale
        case locale, timezone, userAgent, timestamp, pastedLink
        case deviceID = "device_id"
        case userID = "user_id"
    }
}

struct LocaleTag: Codable {
    let languageTag: String
}

public struct DetourResult: Sendable {
    public let processed: Bool
    public let link: DetourLink?
    
    public init(processed: Bool, link: DetourLink?) {
        self.processed = processed
        self.link = link
    }

    public var route: String? { link?.route }
    public var linkType: LinkType? { link?.type }
    public var pathname: String? { link?.pathname }
    public var params: [String: String] { link?.params ?? [:] }
    public var linkURL: URL? { link.flatMap { URL(string: $0.url) } }

    public static func empty() -> DetourResult {
        return DetourResult(processed: true, link: nil)
    }
}

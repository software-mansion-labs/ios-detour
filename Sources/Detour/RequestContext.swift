import AppTrackingTransparency
import Foundation
import Network

/// App and device context sent with every request next to the request's own fields.
struct RequestContext: Encodable {
    var appVersion: String?
    var buildNumber: String?
    var osVersion: String?
    var installSource: String?
    var networkType: String?
    var locale: String?
    var attStatus: String?

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case osVersion = "os_version"
        case installSource = "install_source"
        case networkType = "network_type"
        case locale
        case attStatus = "att_status"
    }

    static func current() -> RequestContext {
        let info = Bundle.main.infoDictionary
        return RequestContext(
            appVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String,
            osVersion: osVersion(),
            installSource: installSource(),
            networkType: NetworkTypeMonitor.shared.currentType,
            locale: Locale.preferredLanguages.first,
            attStatus: attStatus()
        )
    }

    /// match-link keeps `locale` as its v1 array of device signals.
    func forMatchLink() -> RequestContext {
        var context = self
        context.locale = nil
        return context
    }

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return fields
    }

    // Same format as UIDevice.systemVersion, which needs the main actor.
    private static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    }

    // PROVISIONAL: `app_store` / `sandbox` as proposed in the API contract; TestFlight and
    // development builds both report `sandbox`.
    private static func installSource() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return nil }
        return receiptURL.lastPathComponent == "sandboxReceipt" ? "sandbox" : "app_store"
    }

    // Read only: the SDK never shows the tracking prompt and never treats the status as consent.
    private static func attStatus() -> String? {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return nil
        }
    }
}

/// Encodes a request body and its context as one flat JSON object.
struct WithContext<Body: Encodable>: Encodable {
    let body: Body
    let context: RequestContext

    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        try context.encode(to: encoder)
    }
}

final class NetworkTypeMonitor: @unchecked Sendable {
    static let shared = NetworkTypeMonitor()

    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "com.swmansion.detour.network-type"))
    }

    /// nil until the first path update, so the first request after launch can go without it.
    var currentType: String? {
        let path = monitor.currentPath
        guard path.status == .satisfied else { return nil }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        return "other"
    }
}

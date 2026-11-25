import AdServices
import AdSupport
import AppTrackingTransparency
import Detour
import Foundation

/// The part of `DetourAttributionHost` this product uses, so tests can pass their own.
@MainActor
protocol AttributionHosting: AnyObject {
    var isAttributionAllowed: Bool { get }
    var installID: String { get }
    func fetchConversionValueSchema(etag: String?) async -> DetourFetchResult
}

extension DetourAttributionHost: AttributionHosting {}

/// Turns on attribution: `Detour.shared.configure(config, attribution: DetourAttribution())`.
/// Requests feed attribution only with consent to `DetourPurpose.attribution` passed on this
/// launch. The install is attributed from deferred matching, so configure with `autoStart: false`
/// and call `start()` after `setConsent`.
@MainActor
public final class DetourAttribution: DetourAttributionProvider {
    private let store: ConversionValueStore
    private let updater: PostbackUpdating
    private var host: AttributionHosting?
    private var registration: Task<Void, Never>?
    /// `nil` skips the `Info.plist` check.
    private let infoDictionary: [String: Any]?

    public convenience init() {
        self.init(
            store: ConversionValueStore(),
            updater: ApplePostbackUpdater(),
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    }

    init(store: ConversionValueStore, updater: PostbackUpdating, infoDictionary: [String: Any]? = nil) {
        self.store = store
        self.updater = updater
        self.infoDictionary = infoDictionary
    }

    /// The `Info.plist` keys that tell Apple where to send copies of winning postbacks: SKAdNetwork, then AdAttributionKit.
    static let postbackCopyKeys = ["NSAdvertisingAttributionReportEndpoint", "AttributionCopyEndpoint"]

    static func missingPostbackCopyKeys(in info: [String: Any]) -> [String] {
        postbackCopyKeys.filter { ((info[$0] as? String) ?? "").isEmpty }
    }

    public func didStart(_ host: DetourAttributionHost) {
        start(with: host)
    }

    // The schema is asked for on every start, so a rule changed on the server reaches the app on its next launch.
    func start(with host: AttributionHosting) {
        self.host = host
        warnAboutMissingPostbackCopyKeys()
        registerIfAllowed()
        Task {
            store.apply(await host.fetchConversionValueSchema(etag: store.schemaETag))
        }
    }

    public func didLogConversion(_ conversion: DetourConversion) {
        guard let host else { return }
        registerIfAllowed()
        let installID = host.installID
        let count = store.count(conversion.name, installID: installID)
        guard let rule = store.schema.bestRule(for: conversion, count: count),
              rule.fine > store.highestFine(installID: installID)
        else { return }
        let updater = updater
        let registration = registration
        Task {
            // On iOS 15.4+ registering sends the value 0, so it must land before this value, not after.
            await registration?.value
            // Stored only once SKAdNetwork took it, so a failed value is sent again by the next conversion.
            if await updater.update(fine: rule.fine, coarse: rule.coarse, lock: rule.lock ?? false) {
                store.raiseHighestFine(to: rule.fine, installID: installID)
                // A taken value registers the app too; a later registration would send 0 over it.
                store.markRegistered(installID: installID)
            }
        }
    }

    // The token says nothing by itself: the backend asks Apple whether the install came from a
    // Search Ads campaign, so it goes with every install, not only the attributed ones.
    public nonisolated func attributionToken() async -> String? {
        do {
            return try AAAttribution.attributionToken()
        } catch {
            DetourAttributionHost.logWarning("[Detour:ATTRIBUTION] Apple Search Ads token unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    // The app shows the ATT prompt; this only reads the result. Without tracking allowed iOS returns zeros.
    public nonisolated func advertisingID() -> String? {
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return nil }
        return Self.advertisingID(from: ASIdentifierManager.shared().advertisingIdentifier)
    }

    private nonisolated static let zeroAdvertisingID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")

    nonisolated static func advertisingID(from identifier: UUID) -> String? {
        identifier == zeroAdvertisingID ? nil : identifier.uuidString.lowercased()
    }

    private func warnAboutMissingPostbackCopyKeys() {
        guard let infoDictionary else { return }
        let missing = Self.missingPostbackCopyKeys(in: infoDictionary)
        guard !missing.isEmpty else { return }
        DetourAttributionHost.logWarning(
            "[Detour:ATTRIBUTION] Info.plist has no \(missing.joined(separator: ", ")), so Detour gets no copies of winning postbacks. See Attribution in the README."
        )
    }

    // On the first launch with consent, so the install counts for SKAdNetwork attribution. Marked
    // only once SKAdNetwork took it, so a failed attempt runs again on the next start or conversion.
    private func registerIfAllowed() {
        guard let host, host.isAttributionAllowed, registration == nil, !store.isRegistered(installID: host.installID) else { return }
        let installID = host.installID
        let updater = updater
        registration = Task {
            if await updater.register() {
                store.markRegistered(installID: installID)
            }
            registration = nil
        }
    }
}

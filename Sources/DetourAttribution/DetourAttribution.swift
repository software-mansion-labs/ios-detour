import AdServices
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

    public convenience init() {
        self.init(store: ConversionValueStore(), updater: ApplePostbackUpdater())
    }

    init(store: ConversionValueStore, updater: PostbackUpdating) {
        self.store = store
        self.updater = updater
    }

    public func didStart(_ host: DetourAttributionHost) {
        start(with: host)
    }

    // The schema is asked for on every start, so a rule changed on the server reaches the app on its next launch.
    func start(with host: AttributionHosting) {
        self.host = host
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

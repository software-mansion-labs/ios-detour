import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()

    private var isSessionHandled = false
    private var config: DetourConfig?
    private var isStarted = false
    private var runOnStart: [() -> Void] = []
    private var consentToSend: (consent: DetourConsent, text: String?)?
    private var killSwitchReporter: KillSwitchReporter?
    private var deviceIdentifiersReporter: DeviceIdentifiersReporter?
    private var isDeferredMatchInFlight = false
    private var becomeActiveObserver: NSObjectProtocol?
    private var userIdValidator: (@Sendable (String) -> Bool)?
    private let tag = "Detour"

    private init() {} // Private init to force use of 'shared'

    /// Sets up the SDK. With `autoStart: false` analytics, sessions and deferred link matching wait
    /// for `start()`, so the app can wait for its consent platform first. A link the user taps
    /// before that is still routed and counted: the SDK sends the link click (link URL, app version,
    /// OS version, device model), because your plan's click limit applies to it.
    /// Pass `DetourAttribution()` from the DetourAttribution product as `attribution` to turn on
    /// attribution. Only the first config is used.
    public func configure(
        _ config: DetourConfig,
        attribution: DetourAttributionProvider? = nil,
        autoStart: Bool = true
    ) {
        if self.config != nil {
            DetourLogger.warn(tag, "[Detour:CONFIG] configure called again; the first config is kept.")
        } else {
            self.config = config
            AttributionMode.register(attribution)
            applyUserIdValidator(config.userIdValidator)
            _ = InstallStore.shared.deviceID
            SdkConfigStore.shared.load(appID: config.appID)
            DetourAnalytics.shared.prepare(config: config)
            refreshSdkConfig(config)
            killSwitchReporter = KillSwitchReporter(store: .shared) { enabled, date in
                await SdkNetwork.sendKillSwitch(
                    enabled: enabled, at: date, config: config,
                    sdkPackage: AttributionMode.sdkPackage, deviceID: InstallStore.shared.deviceID
                )
            }
            killSwitchReporter?.sync()
            setUpDeviceIdentifiersReporter(config)
            if let consentToSend {
                self.consentToSend = nil
                sendConsent(consentToSend.consent, text: consentToSend.text, config: config)
            }
        }

        if autoStart {
            start()
        }
    }

    /// Starts analytics, sessions and deferred link matching. Call it after `configure`.
    public func start() {
        guard let config else {
            DetourLogger.warn(tag, "[Detour:CONFIG] start called before configure; nothing started.")
            return
        }

        isStarted = true
        DetourAnalytics.shared.mountForStart(config: config)
        AttributionMode.start(config: config)
        let waiting = runOnStart
        runOnStart = []
        waiting.forEach { $0() }
        deviceIdentifiersReporter?.sync()
    }

    private func setUpDeviceIdentifiersReporter(_ config: DetourConfig) {
        deviceIdentifiersReporter = DeviceIdentifiersReporter(
            canSend: { [weak self] in
                // After the first match, so the server has the install to attach them to; only as
                // `mmp`, because the server keeps nothing from `core`.
                guard let self, self.isStarted, !self.isDeferredMatchInFlight, !InstallStore.shared.isFirstLaunch else { return false }
                return AttributionMode.sdkPackage == .mmp
            },
            current: { AttributionMode.deviceIdentifiers(for: AttributionMode.sdkPackage) },
            deviceID: { InstallStore.shared.deviceID },
            send: { fields in
                await SdkNetwork.sendDeviceIdentifiers(fields, config: config, sdkPackage: .mmp)
            }
        )
        // Also after the ATT prompt closes: the app becomes active again with the new status.
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deviceIdentifiersReporter?.sync() }
        }
    }

    // Once per launch, so a value changed on the server reaches the app on its next launch.
    // shortcut: with the SDK off, the first launch never fetches, so its gates stay closed until the
    // next launch even after setEnabled(true); fetch in setEnabled too if that case matters.
    private func refreshSdkConfig(_ config: DetourConfig) {
        guard InstallStore.shared.isEnabled else { return }
        Task {
            let store = SdkConfigStore.shared
            let result = await SdkNetwork.fetchConfig(config: config, sdkPackage: AttributionMode.sdkPackage, etag: store.etag)
            store.apply(result, appID: config.appID)
            // Also when nothing changed: on a first launch the gates waited for this fetch.
            consentInputsChanged()
        }
    }

    /// Passes the user's choice from your consent platform. Call it on every launch once the
    /// platform has the choice, not only when it changes: a choice stored on an earlier launch
    /// can stop requests for a purpose, but a grant counts only once passed again on this launch.
    /// The call is cheap: a choice the Detour server already has, with no `timestamp` of its own,
    /// is not sent again.
    /// `consentText` is the text the user agreed to, stored once per version on the Detour server.
    public func setConsent(_ consent: DetourConsent, consentText: String? = nil) {
        var consent = consent
        if consent.schemaVersion == nil {
            consent.schemaVersion = SdkConfigStore.shared.current.schemaVersion
        }
        let toSend = ConsentStore.record(consent, deviceID: InstallStore.shared.deviceID)
        warnAboutConsentPitfalls(consent)
        consentInputsChanged()

        guard let toSend else { return }
        if let config {
            sendConsent(toSend, text: consentText, config: config)
        } else {
            consentToSend = (toSend, consentText)
        }
    }

    /// Checks again the requests that wait, after consent, the server config or the kill switch changed.
    private func consentInputsChanged() {
        DetourAnalytics.shared.reevaluateWaiting()
        AttributionMode.reevaluate()
        deviceIdentifiersReporter?.sync()
    }

    // PROVISIONAL: how long after setConsent the SDK expects start() before it warns.
    static let startAfterConsentGraceNanoseconds: UInt64 = 5_000_000_000

    private func warnAboutConsentPitfalls(_ consent: DetourConsent) {
        if consent.purposes[DetourPurpose.analytics] == nil {
            ConsentWarnings.warnOnce(
                "consentWithoutAnalytics",
                "setConsent has no analytics key, so analytics stops: a purpose missing from the map is not granted."
            )
        }
        guard ConsentWarnings.isDevelopment, !isStarted else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startAfterConsentGraceNanoseconds)
            guard let self, !self.isStarted else { return }
            ConsentWarnings.warnOnce(
                "consentWithoutStart",
                "setConsent was called, but start() was not. With autoStart: false, analytics and deferred link matching wait for it."
            )
        }
    }

    /// What the SDK does now: started, enabled, consent on this launch, and each purpose's decision.
    public func getStatus() -> DetourStatus {
        let passed = ConsentStore.passedThisLaunch
        var purposeIDs = DetourPurpose.builtIn
        purposeIDs.formUnion(SdkConfigStore.shared.current.consentGateDefaults.keys)
        if let passed {
            purposeIDs.formUnion(passed.purposes.keys)
        }
        var purposes: [String: DetourStatus.Decision] = [:]
        for purpose in purposeIDs {
            purposes[purpose] = DetourStatus.Decision(ConsentGate.decision(for: purpose))
        }
        return DetourStatus(
            isStarted: isStarted,
            isEnabled: InstallStore.shared.isEnabled,
            hasConsentThisLaunch: passed != nil,
            purposes: purposes
        )
    }

    private func sendConsent(_ consent: DetourConsent, text: String?, config: DetourConfig) {
        guard InstallStore.shared.isEnabled else { return }
        let deviceID = InstallStore.shared.deviceID
        let userID = UserIdStore.current
        let sdkPackage = AttributionMode.sdkPackage
        Task {
            if await SdkNetwork.sendConsent(
                consent, consentText: text, config: config, sdkPackage: sdkPackage, deviceID: deviceID, userID: userID
            ) {
                ConsentStore.markConfirmed(consent, deviceID: deviceID)
            }
        }
    }

    /// `false` turns the SDK off for this install, also on later launches, until `setEnabled(true)`.
    /// While off it sends nothing: no analytics, sessions, conversions, consent or deferred link
    /// matching. Links the user taps are still routed. The device ID does not change.
    public func setEnabled(_ enabled: Bool) {
        guard InstallStore.shared.setEnabled(enabled, at: Date()) else { return }
        // Drops what waited for consent when the SDK goes off.
        consentInputsChanged()
        killSwitchReporter?.sync()
    }

    private func whenStarted(_ work: @escaping () -> Void) {
        if isStarted {
            work()
        } else {
            runOnStart.append(work)
        }
    }

    /// `configure` and `start` in one call, as in SDK 1.x. After `configure(_:autoStart: false)`
    /// it does not start anything; call `start()` instead.
    public func mountAnalytics(config: DetourConfig) {
        if self.config == nil {
            configure(config)
        } else if isStarted {
            start()
        }
    }

    /// Sets the app's own user identifier, sent with every later request. `nil` removes it.
    /// A stable account ID: the same for the user on every install, never a guest or anonymous ID.
    /// Must not be an e-mail address or a phone number. A value that is empty, longer than 256
    /// UTF-16 code units or rejected by `DetourConfig.userIdValidator` is dropped and clears the stored one.
    /// The validator checks every `setUserId` value and the stored one once the config is passed
    /// to `configure` (or `resolveInitialLink` / `mountAnalytics`).
    public func setUserId(_ userId: String?) {
        guard let userId else {
            UserIdStore.current = nil
            return
        }

        // A rejected value also clears the previous one, so requests never go out
        // with the identifier of the user the app has just switched away from.
        guard isUserIdAccepted(userId) else {
            UserIdStore.current = nil
            return
        }

        UserIdStore.current = userId
    }

    func applyUserIdValidator(_ validator: (@Sendable (String) -> Bool)?) {
        userIdValidator = validator
        // A value set before the config or stored by an earlier app version never met this validator.
        if let storedUserId = UserIdStore.current, !isUserIdAccepted(storedUserId) {
            UserIdStore.current = nil
        }
    }

    private func isUserIdAccepted(_ userId: String) -> Bool {
        // The backend rejects the whole request otherwise, and on first launch the deferred link is lost.
        guard !userId.isEmpty, userId.utf16.count <= 256 else {
            DetourLogger.warn(tag, "[Detour:IDENTITY] user ID has the wrong format (empty or longer than 256 characters); not stored or sent.")
            return false
        }
        guard UserIdPolicy.isAllowed(userId), userIdValidator?(userId) ?? true else {
            DetourLogger.warn(tag, "[Detour:IDENTITY] user ID rejected by the validator; not stored or sent.")
            return false
        }
        return true
    }

    private func markSessionHandled() {
        InstallStore.shared.markFirstLaunchHandled()
        isSessionHandled = true
    }

    public func unmountAnalytics() {
        DetourAnalytics.unmount()
    }

    public func resetSession(allowDeferredRetry: Bool = false) {
        isSessionHandled = false
        DetourLogger.debug(tag, "Session reset")
        if allowDeferredRetry {
            InstallStore.shared.resetFirstLaunch()
            DetourLogger.debug(tag, "Deferred retry enabled - first-launch flag reset")
        }
    }

    private func filterNonWebUrlLikeLinks(_ result: DetourResult, mode: LinkProcessingMode) -> DetourResult {
        guard mode != .all else { return result }
        guard let link = result.link else { return result }

        let parsed = URL(string: link.url)
        let isWeb = LinkUtils.isWebUrl(link.url, parsedUrl: parsed)

        if LinkUtils.looksLikeUrl(link.url), !isWeb {
            DetourLogger.debug(tag, "Non-web URL-like link filtered by mode \(mode.rawValue)")
            return .empty()
        }

        return result
    }

    private func resolveLink(
        _ rawLink: String,
        config: DetourConfig?,
        typeOverride: LinkType? = nil,
        visitedShortLinks: Set<String> = []
    ) async -> DetourLink? {
        if LinkUtils.isInfrastructureUrl(rawLink) {
            DetourLogger.debug(tag, "Ignored infrastructure URL: \(rawLink)")
            return nil
        }

        let mode = config?.linkProcessingMode ?? .all

        if !LinkUtils.looksLikeUrl(rawLink) {
            return LinkUtils.makeDetourLink(fromPath: rawLink, type: typeOverride ?? .verified)
        }

        let normalized = LinkUtils.normalizeRawLink(rawLink)
        guard let url = LinkUtils.parseUrl(normalized) else {
            let isWeb = LinkUtils.isWebUrl(rawLink)
            if !isWeb && mode != .all {
                DetourLogger.debug(tag, "Custom scheme link ignored in mode \(mode.rawValue)")
                return nil
            }

            DetourLogger.warn(tag, "[Detour:TYPE_ERROR] Failed to parse URL, falling back to raw string")
            let fallbackType = typeOverride ?? (isWeb ? .verified : .scheme)
            return DetourLink(
                url: rawLink,
                route: rawLink,
                pathname: rawLink,
                params: [:],
                type: fallbackType
            )
        }

        let isWeb = LinkUtils.isWebUrl(rawLink, parsedUrl: url)
        if !isWeb && mode != .all {
            DetourLogger.debug(tag, "Custom scheme link ignored in mode \(mode.rawValue)")
            return nil
        }

        let type = typeOverride ?? (isWeb ? .verified : .scheme)

        if isWeb {
            let pathSegments = url.path.split(separator: "/").map(String.init)
            let isSingleSegmentPath = pathSegments.count == 1 && !pathSegments[0].isEmpty

            if isSingleSegmentPath, let config {
                var visited = visitedShortLinks
                visited.insert(normalized)

                if let resolvedUrl = await DetourNetwork.resolveShortLink(config: config, sdkPackage: AttributionMode.sdkPackage, url: rawLink) {
                    let normalizedResolved = LinkUtils.normalizeRawLink(resolvedUrl.absoluteString)
                    if !visited.contains(normalizedResolved) {
                        return await resolveLink(
                            normalizedResolved,
                            config: config,
                            visitedShortLinks: visited
                        )
                    }
                }
            }
        }

        return LinkUtils.makeDetourLink(from: url, type: type)
    }

    private func browsingWebActivities(
        from launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> [NSUserActivity] {
        guard let activityDict = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] else {
            return []
        }

        return activityDict.values.compactMap { value in
            guard let activity = value as? NSUserActivity else { return nil }
            return activity.activityType == NSUserActivityTypeBrowsingWeb ? activity : nil
        }
    }

    private func browsingWebActivities(from connectionOptions: UIScene.ConnectionOptions) -> [NSUserActivity] {
        connectionOptions.userActivities.filter { $0.activityType == NSUserActivityTypeBrowsingWeb }
    }

    // `finish` also reports ready for the UI; `report` alone is for the wait before the match.
    private func resolveDeferredInitialLink(
        config: DetourConfig,
        report: ReadyForUIReport,
        finish: @escaping @MainActor @Sendable (DetourResult) -> Void
    ) {
        if !InstallStore.shared.isFirstLaunch {
            DetourLogger.debug(tag, "Not first launch")
            isSessionHandled = true
            finish(.empty())
            return
        }

        // Reported first, so an app that holds its UI until then can still ask for consent. The
        // first-launch flag is stored only when matching runs, so an app closed before `start()`
        // or before the consent decision still matches on its next launch.
        isSessionHandled = true
        DetourLogger.debug(tag, "First launch detected, processing deferred link")
        if !isStarted || AttributionMode.isWaitingForConsent {
            report.ready()
        }
        whenStarted { [weak self] in
            if AttributionMode.isWaitingForConsent {
                let isStoredGrantWarned = ConsentGate.warnIfStoredGrantWaits(DetourPurpose.attribution)
                if !isStoredGrantWarned {
                    ConsentWarnings.warnOnce(
                        "firstMatchWaits",
                        "The first deferred link match waits for consent to attribution. Pass it with setConsent."
                    )
                }
            }
            AttributionMode.whenDecided { [weak self] in
                self?.matchDeferredLink(config: config, finish: finish)
            }
        }
    }

    private func matchDeferredLink(
        config: DetourConfig,
        finish: @escaping @MainActor @Sendable (DetourResult) -> Void
    ) {
        markSessionHandled()
        guard InstallStore.shared.isEnabled else {
            DetourLogger.debug(tag, "SDK disabled; deferred link matching skipped")
            finish(.empty())
            return
        }
        DetourLogger.debug(tag, "Using signal-based matching")
        isDeferredMatchInFlight = true

        Task { [weak self] in
            // One decision for the header and the token: an `asa_token` never goes out as `core`.
            // The token is read while the signals are collected.
            let sdkPackage = AttributionMode.sdkPackage
            let identifiers = AttributionMode.deviceIdentifiers(for: sdkPackage)
            async let asaToken = AttributionMode.attributionToken(for: sdkPackage)
            var matchRequest = await DeviceUtils.collectSignals(
                shouldUseClipboard: config.shouldUseClipboard,
                deviceID: InstallStore.shared.deviceID,
                userID: UserIdStore.current
            )
            matchRequest.asaToken = await asaToken
            matchRequest.advertisingID = identifiers.advertisingID
            matchRequest.idfv = identifiers.idfv
            DetourNetwork.matchLink(
                config: config, sdkPackage: sdkPackage, request: matchRequest, linkType: .deferred
            ) { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        finish(result)
                        return
                    }
                    self.isDeferredMatchInFlight = false
                    self.deviceIdentifiersReporter?.sync()

                    let filteredResult = self.filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
                    if filteredResult.link == nil {
                        DetourLogger.debug(self.tag, "No deferred link matched")
                    } else {
                        DetourLogger.debug(self.tag, "Deferred link matched successfully")
                    }
                    finish(filteredResult)
                }
            }
        }
    }
    
    // Converts a URL into a DetourResult with a parsed route.
    public func processLink(_ url: URL) -> DetourResult {
        if LinkUtils.isInfrastructureUrl(url.absoluteString) {
            DetourLogger.debug(tag, "Ignored infrastructure URL: \(url.absoluteString)")
            return .empty()
        }

        let linkType = LinkUtils.detectLinkType(from: url)
        switch linkType {
        case .verified:
            DetourLogger.debug(tag, "Processing Universal Link")
        case .scheme:
            DetourLogger.debug(tag, "Processing Scheme Link")
        case .deferred:
            DetourLogger.debug(tag, "Processing Deferred Link")
        }
        let link = LinkUtils.makeDetourLink(from: url, type: linkType)
        return DetourResult(processed: true, link: link)
    }

    // Processes URL and optionally resolves web short-links when config is provided.
    public func processLink(_ url: URL, config: DetourConfig?) async -> DetourResult {
        // The click is Detour's measurement, not routing, so the kill switch stops it.
        if LinkUtils.detectLinkType(from: url) == .verified, let config, InstallStore.shared.isEnabled {
            let isAllowed = await DetourNetwork.sendUniversalLinkClick(
                config: config, sdkPackage: AttributionMode.sdkPackage, url: url.absoluteString
            )
            if !isAllowed {
                return .empty()
            }
        }
        return await processLink(url.absoluteString, config: config)
    }

    // Converts a raw link string into a DetourResult with route and link type.
    // If config is provided, web short-links are resolved before parsing.
    public func processLink(_ rawLink: String, config: DetourConfig? = nil) async -> DetourResult {
        let resolvedLink = await resolveLink(rawLink, config: config)
        if resolvedLink == nil {
            DetourLogger.debug(tag, "No matching link found")
        }
        return DetourResult(processed: true, link: resolvedLink)
    }
    
    /// Routes the link the app was opened with, or matches the deferred link on the first launch,
    /// and passes it to `completion`. `onReadyForUI` is called once, before the
    /// completion or before the SDK starts waiting for `start()` or for consent to attribution,
    /// so an app that holds its UI until then can show its consent prompt; a deferred link found
    /// after that still arrives in `completion`.
    public func resolveInitialLink(
        config: DetourConfig,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        onReadyForUI: (@MainActor () -> Void)? = nil,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        resolveInitialLink(
            config: config,
            openURL: launchOptions?[.url] as? URL,
            activities: browsingWebActivities(from: launchOptions),
            report: ReadyForUIReport(onReadyForUI),
            completion: completion
        )
    }

    /// The scene version of `resolveInitialLink(config:launchOptions:onReadyForUI:completion:)`.
    public func resolveInitialLink(
        config: DetourConfig,
        connectionOptions: UIScene.ConnectionOptions,
        onReadyForUI: (@MainActor () -> Void)? = nil,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        resolveInitialLink(
            config: config,
            openURL: connectionOptions.urlContexts.first?.url,
            activities: browsingWebActivities(from: connectionOptions),
            report: ReadyForUIReport(onReadyForUI),
            completion: completion
        )
    }

    private func resolveInitialLink(
        config: DetourConfig,
        openURL: URL?,
        activities: [NSUserActivity],
        report: ReadyForUIReport,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        mountAnalytics(config: config)

        let finish: @MainActor @Sendable (DetourResult) -> Void = { result in
            report.ready()
            completion(result)
        }

        if isSessionHandled {
            DetourLogger.debug(tag, "Session already handled")
            finish(.empty())
            return
        }

        if config.linkProcessingMode != .deferredOnly {
            if let openURL, !LinkUtils.isInfrastructureUrl(openURL.absoluteString) {
                DetourLogger.debug(tag, "Processing launch URL")
                markSessionHandled()
                Task {
                    finish(await processLink(openURL.absoluteString, config: config))
                }
                return
            }

            if let universalURL = activities.compactMap(\.webpageURL).first,
               !LinkUtils.isInfrastructureUrl(universalURL.absoluteString)
            {
                DetourLogger.debug(tag, "Processing Universal Link")
                markSessionHandled()
                Task {
                    finish(await processLink(universalURL, config: config))
                }
                return
            }

            if !activities.isEmpty {
                DetourLogger.debug(tag, "Universal Link userActivity detected - awaiting continueUserActivity callback")
                markSessionHandled()
                // UIApplicationDelegate will invoke continueUserActivity next.
                finish(.empty())
                return
            }
        }

        DetourLogger.debug(tag, "Falling back to deferred link resolution")
        resolveDeferredInitialLink(config: config, report: report, finish: finish)
    }

}


/// Calls `onReadyForUI` once, whichever path gets there first.
@MainActor
final class ReadyForUIReport {
    private var onReady: (@MainActor () -> Void)?

    init(_ onReady: (@MainActor () -> Void)?) {
        self.onReady = onReady
    }

    func ready() {
        let pending = onReady
        onReady = nil
        pending?()
    }
}

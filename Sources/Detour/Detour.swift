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
    private var userIdValidator: (@Sendable (String) -> Bool)?
    private let tag = "Detour"

    private init() {} // Private init to force use of 'shared'

    /// Sets up the SDK. With `autoStart: false` analytics, sessions and deferred link matching wait
    /// for `start()`, so the app can wait for its consent platform first. A link the user taps
    /// before that is still routed and counted: the SDK sends the link click (link URL, app version,
    /// OS version, device model), because your plan's click limit applies to it.
    /// Only the first config is used.
    public func configure(_ config: DetourConfig, autoStart: Bool = true) {
        if self.config != nil {
            DetourLogger.warn(tag, "[Detour:CONFIG] configure called again; the first config is kept.")
        } else {
            self.config = config
            applyUserIdValidator(config.userIdValidator)
            _ = InstallStore.shared.deviceID
            SdkConfigStore.shared.load(appID: config.appID)
            refreshSdkConfig(config)
            killSwitchReporter = KillSwitchReporter(store: .shared) { enabled, date in
                await SdkNetwork.sendKillSwitch(enabled: enabled, at: date, config: config, deviceID: InstallStore.shared.deviceID)
            }
            killSwitchReporter?.sync()
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
        DetourAnalytics.mount(config: config)
        let waiting = runOnStart
        runOnStart = []
        waiting.forEach { $0() }
    }

    // Once per launch, so a value changed on the server reaches the app on its next launch.
    private func refreshSdkConfig(_ config: DetourConfig) {
        guard InstallStore.shared.isEnabled else { return }
        Task {
            let store = SdkConfigStore.shared
            let result = await SdkNetwork.fetchConfig(config: config, etag: store.etag)
            if store.apply(result, appID: config.appID) {
                DetourAnalytics.shared.reevaluateWaiting()
            }
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
        DetourAnalytics.shared.reevaluateWaiting()

        guard let toSend else { return }
        if let config {
            sendConsent(toSend, text: consentText, config: config)
        } else {
            consentToSend = (toSend, consentText)
        }
    }

    private func sendConsent(_ consent: DetourConsent, text: String?, config: DetourConfig) {
        guard InstallStore.shared.isEnabled else { return }
        let deviceID = InstallStore.shared.deviceID
        let userID = UserIdStore.current
        Task {
            if await SdkNetwork.sendConsent(consent, consentText: text, config: config, deviceID: deviceID, userID: userID) {
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
        DetourAnalytics.shared.reevaluateWaiting()
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

                if let resolvedUrl = await DetourNetwork.resolveShortLink(config: config, url: rawLink) {
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

    private func resolveDeferredInitialLink(
        config: DetourConfig,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        if !InstallStore.shared.isFirstLaunch {
            DetourLogger.debug(tag, "Not first launch")
            isSessionHandled = true
            completion(.empty())
            return
        }

        // The first-launch flag is stored only when matching runs, so an app closed before
        // `start()` still matches on its next launch.
        isSessionHandled = true
        DetourLogger.debug(tag, "First launch detected, processing deferred link")
        whenStarted { [weak self] in
            self?.matchDeferredLink(config: config, completion: completion)
        }
    }

    private func matchDeferredLink(
        config: DetourConfig,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        markSessionHandled()
        guard InstallStore.shared.isEnabled else {
            DetourLogger.debug(tag, "SDK disabled; deferred link matching skipped")
            completion(.empty())
            return
        }
        DetourLogger.debug(tag, "Using signal-based matching")

        Task { [weak self] in
            let matchRequest = await DeviceUtils.collectSignals(
                shouldUseClipboard: config.shouldUseClipboard,
                deviceID: InstallStore.shared.deviceID,
                userID: UserIdStore.current
            )
            DetourNetwork.matchLink(config: config, request: matchRequest, linkType: .deferred) { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        completion(result)
                        return
                    }

                    let filteredResult = self.filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
                    if filteredResult.link == nil {
                        DetourLogger.debug(self.tag, "No deferred link matched")
                    } else {
                        DetourLogger.debug(self.tag, "Deferred link matched successfully")
                    }
                    completion(filteredResult)
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
            let clickResult = await DetourNetwork.sendUniversalLinkClick(config: config, url: url.absoluteString)
            if !clickResult.allowed {
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
    
    public func resolveInitialLink(
            config: DetourConfig,
            launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
            completion: @escaping @Sendable (DetourResult) -> Void
        ) {
            mountAnalytics(config: config)
            
            func returnEmpty() { completion(.empty()) }
            
            if isSessionHandled {
                DetourLogger.debug(tag, "Session already handled")
                returnEmpty()
                return
            }
            
            if config.linkProcessingMode != .deferredOnly {
                if let launchURL = launchOptions?[.url] as? URL,
                   !LinkUtils.isInfrastructureUrl(launchURL.absoluteString)
                {
                    DetourLogger.debug(tag, "Processing launch URL")
                    markSessionHandled()
                    Task {
                        let result = await processLink(launchURL.absoluteString, config: config)
                        completion(result)
                    }
                    return
                }

                let activities = browsingWebActivities(from: launchOptions)
                if let universalURL = activities.compactMap(\.webpageURL).first,
                   !LinkUtils.isInfrastructureUrl(universalURL.absoluteString)
                {
                    DetourLogger.debug(tag, "Processing Universal Link")
                    markSessionHandled()
                    Task {
                        let result = await processLink(universalURL, config: config)
                        completion(result)
                    }
                    return
                }

                if !activities.isEmpty {
                    DetourLogger.debug(tag, "Universal Link userActivity detected - awaiting continueUserActivity callback")
                    markSessionHandled()
                    // UIApplicationDelegate will invoke continueUserActivity next.
                    returnEmpty()
                    return
                }
            }

            DetourLogger.debug(tag, "Falling back to deferred link resolution")
            resolveDeferredInitialLink(config: config, completion: completion)
        }

    public func resolveInitialLink(
        config: DetourConfig,
        connectionOptions: UIScene.ConnectionOptions,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        mountAnalytics(config: config)

        func returnEmpty() { completion(.empty()) }

        if isSessionHandled {
            DetourLogger.debug(tag, "Session already handled")
            returnEmpty()
            return
        }

        if config.linkProcessingMode != .deferredOnly {
            if let openURL = connectionOptions.urlContexts.first?.url,
               !LinkUtils.isInfrastructureUrl(openURL.absoluteString)
            {
                DetourLogger.debug(tag, "Processing launch URL")
                markSessionHandled()
                Task {
                    let result = await processLink(openURL.absoluteString, config: config)
                    completion(result)
                }
                return
            }

            let activities = browsingWebActivities(from: connectionOptions)
            if let universalURL = activities.compactMap(\.webpageURL).first,
               !LinkUtils.isInfrastructureUrl(universalURL.absoluteString)
            {
                DetourLogger.debug(tag, "Processing Universal Link")
                markSessionHandled()
                Task {
                    let result = await processLink(universalURL, config: config)
                    completion(result)
                }
                return
            }

            if !activities.isEmpty {
                DetourLogger.debug(tag, "Universal Link userActivity detected - awaiting continue callback")
                markSessionHandled()
                returnEmpty()
                return
            }
        }

        DetourLogger.debug(tag, "Falling back to deferred link resolution")
        resolveDeferredInitialLink(config: config, completion: completion)
    }
    
}

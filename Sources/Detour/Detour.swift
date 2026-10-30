import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()

    private var isSessionHandled = false
    private var userIdValidator: (@Sendable (String) -> Bool)?
    private let tag = "Detour"
    
    private init() {} // Private init to force use of 'shared'

    public func mountAnalytics(config: DetourConfig) {
        userIdValidator = config.userIdValidator
        DetourAnalytics.mount(config: config)
    }

    /// Sets the app's own user identifier, sent with every later request. `nil` removes it.
    /// Must not be an e-mail address or a phone number. `DetourConfig.userIdValidator` applies only
    /// after the config was passed to `resolveInitialLink` or `mountAnalytics`, so call this after them.
    public func setUserId(_ userId: String?) {
        guard let userId else {
            UserIdStore.current = nil
            return
        }

        // A rejected value also clears the previous one, so requests never go out
        // with the identifier of the user the app has just switched away from.
        guard UserIdPolicy.isAllowed(userId), userIdValidator?(userId) ?? true else {
            DetourLogger.warn(tag, "[Detour:IDENTITY] setUserId value rejected by the validator; not stored or sent.")
            UserIdStore.current = nil
            return
        }

        UserIdStore.current = userId
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

        markSessionHandled()
        DetourLogger.debug(tag, "First launch detected, processing deferred link")
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
        if LinkUtils.detectLinkType(from: url) == .verified, let config {
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

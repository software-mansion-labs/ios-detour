import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()

    private var session = InitialLinkSession()
    private var linkOpens = LinkOpens()
    private var universalLinkClicks = UniversalLinkClickRecorder()
    private let tag = "Detour"

    private init() {} // Private init to force use of 'shared'

    public func mountAnalytics(config: DetourConfig) {
        DetourAnalytics.mount(config: config)
    }

    public func unmountAnalytics() {
        DetourAnalytics.unmount()
    }

    public func resetSession(allowDeferredRetry: Bool = false) {
        session.reset()
        DetourLogger.debug(tag, "Session reset")
        if allowDeferredRetry {
            StorageUtils.resetFirstEntrance()
            DetourLogger.debug(tag, "Deferred retry enabled - first entrance flag reset")
        }
    }

    // Tests pass their own clock, so time windows can pass without waiting.
    func resetLinkState(now: @escaping () -> TimeInterval) {
        linkOpens = LinkOpens(now: now)
        universalLinkClicks = UniversalLinkClickRecorder(now: now)
    }

    private func filterNonWebUrlLikeLinks(_ result: DetourResult, mode: LinkProcessingMode) -> DetourResult {
        guard !mode.handles(.scheme) else { return result }
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
            if !isWeb && !mode.handles(.scheme) {
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
        if !isWeb && !mode.handles(.scheme) {
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
        guard StorageUtils.isFirstEntrance() else {
            DetourLogger.debug(tag, "Not first launch")
            completion(.empty())
            return
        }

        StorageUtils.markFirstEntrance()
        DetourLogger.debug(tag, "First launch detected, processing deferred link")
        DetourLogger.debug(tag, "Using probabilistic matching")

        Task {
            let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
            let result = await DetourNetwork.matchLink(config: config, fingerprint: fingerprint, linkType: .deferred)

            if session.isDeferredLinkReplaced {
                DetourLogger.debug(tag, "Deferred link dropped, the scene launch link opened instead")
                completion(.empty())
                return
            }

            let filteredResult = filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
            if filteredResult.link == nil {
                DetourLogger.debug(tag, "No deferred link matched")
            } else {
                DetourLogger.debug(tag, "Deferred link matched successfully")
            }
            completion(filteredResult)
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
    // Returns an empty result when an earlier call already delivered this link open.
    public func processLink(_ url: URL, config: DetourConfig?) async -> DetourResult {
        guard linkOpens.claimCallbackLink(url.absoluteString) else {
            DetourLogger.debug(tag, "Link already delivered for this open")
            return .empty()
        }
        return await openLink(url, config: config)
    }

    private func openLink(_ url: URL, config: DetourConfig?) async -> DetourResult {
        let linkType = LinkUtils.detectLinkType(from: url)
        if let mode = config?.linkProcessingMode, !mode.handles(linkType) {
            DetourLogger.debug(tag, "Link of type \(linkType.rawValue) ignored in mode \(mode.rawValue)")
            return .empty()
        }

        // Apps keep working when the click cannot be saved. Limits apply only on an explicit deny.
        if linkType == .verified, let config,
           await universalLinkClicks.record(config: config, url: url.absoluteString) == .denied {
            return .empty()
        }
        return await processLink(url.absoluteString, config: config)
    }

    private func openLaunchLink(
        _ url: URL,
        config: DetourConfig,
        source: LaunchSource,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        StorageUtils.markFirstEntrance()

        guard linkOpens.claimLaunchLink(url.absoluteString, source: source) else {
            DetourLogger.debug(tag, "Launch link already delivered by processLink")
            completion(.empty())
            return
        }

        Task {
            let result = await openLink(url, config: config)
            completion(result)
        }
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
        let activities = browsingWebActivities(from: launchOptions)
        let launch = LaunchContext(
            candidateURLs: [launchOptions?[.url] as? URL] + activities.map(\.webpageURL),
            hasBrowsingActivity: !activities.isEmpty,
            source: .launchOptions
        )
        resolveInitialLink(config: config, launch: launch, completion: completion)
    }

    public func resolveInitialLink(
        config: DetourConfig,
        connectionOptions: UIScene.ConnectionOptions,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        let activities = browsingWebActivities(from: connectionOptions)
        let launch = LaunchContext(
            candidateURLs: [connectionOptions.urlContexts.first?.url] + activities.map(\.webpageURL),
            hasBrowsingActivity: !activities.isEmpty,
            source: .connectionOptions
        )
        resolveInitialLink(config: config, launch: launch, completion: completion)
    }

    func resolveInitialLink(
        config: DetourConfig,
        launch: LaunchContext,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        mountAnalytics(config: config)

        switch session.action(for: launch, mode: config.linkProcessingMode) {
        case let .open(url):
            DetourLogger.debug(tag, session.isDeferredLinkReplaced ? "Processing scene launch link instead of the deferred link" : "Processing launch link")
            openLaunchLink(url, config: config, source: launch.source, completion: completion)
        case .awaitContinueCallback:
            DetourLogger.debug(tag, "Universal Link userActivity detected - awaiting continue callback")
            StorageUtils.markFirstEntrance()
            completion(.empty())
        case .resolveDeferred:
            DetourLogger.debug(tag, "Falling back to deferred link resolution")
            resolveDeferredInitialLink(config: config, completion: completion)
        case .skip:
            DetourLogger.debug(tag, "Session already handled")
            completion(.empty())
        }
    }
    
}

import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()
    
    private var isSessionHandled = false
    
    private init() {} // Private init to force use of 'shared'

    public func mountAnalytics(config: DetourConfig) {
        DetourAnalytics.mount(config: config)
    }

    public func unmountAnalytics() {
        DetourAnalytics.unmount()
    }

    private func filterNonWebUrlLikeLinks(_ result: DetourResult, mode: LinkProcessingMode) -> DetourResult {
        guard mode != .all else { return result }
        guard let link = result.link else { return result }

        let parsed = URL(string: link.url)
        let isWeb = LinkUtils.isWebUrl(link.url, parsedUrl: parsed)

        if LinkUtils.looksLikeUrl(link.url), !isWeb {
            return .empty()
        }

        return result
    }

    private func resolveLink(
        _ rawLink: String,
        config: DetourConfig?,
        typeOverride: LinkType? = nil
    ) async -> DetourLink? {
        if LinkUtils.isInfrastructureUrl(rawLink) {
            return nil
        }

        let mode = config?.linkProcessingMode ?? .all

        if !LinkUtils.looksLikeUrl(rawLink) {
            return LinkUtils.makeDetourLink(fromPath: rawLink, type: typeOverride ?? .verified)
        }

        let normalized = LinkUtils.normalizeRawLink(rawLink)
        guard let url = URL(string: normalized) else {
            let isWeb = LinkUtils.isWebUrl(rawLink)
            if !isWeb && mode != .all {
                return nil
            }

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
            return nil
        }

        let type = typeOverride ?? (isWeb ? .verified : .scheme)

        if isWeb {
            let pathSegments = url.path.split(separator: "/").map(String.init)
            let isSingleSegmentPath = pathSegments.count == 1 && !pathSegments[0].isEmpty

            if isSingleSegmentPath, let config {
                if let resolvedUrl = await DetourNetwork.resolveShortLink(config: config, url: rawLink),
                   resolvedUrl.absoluteString != normalized
                {
                    return await resolveLink(resolvedUrl.absoluteString, config: config)
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
    
    // Converts a URL into a DetourResult with a parsed route.
    public func processLink(_ url: URL) -> DetourResult {
        if LinkUtils.isInfrastructureUrl(url.absoluteString) {
            return .empty()
        }

        let linkType = LinkUtils.detectLinkType(from: url)
        let link = LinkUtils.makeDetourLink(from: url, type: linkType)
        return DetourResult(processed: true, link: link)
    }

    // Processes URL and optionally resolves web short-links when config is provided.
    public func processLink(_ url: URL, config: DetourConfig?) async -> DetourResult {
        await processLink(url.absoluteString, config: config)
    }

    // Converts a raw link string into a DetourResult with route and link type.
    // If config is provided, web short-links are resolved before parsing.
    public func processLink(_ rawLink: String, config: DetourConfig? = nil) async -> DetourResult {
        let resolvedLink = await resolveLink(rawLink, config: config)
        return DetourResult(processed: true, link: resolvedLink)
    }
    
    public func resolveInitialLink(
            config: DetourConfig,
            launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
            completion: @escaping @Sendable (DetourResult) -> Void
        ) {
            mountAnalytics(config: config)
            
            func returnEmpty() { completion(.empty()) }
            
            if isSessionHandled { returnEmpty(); return }
            isSessionHandled = true
            
            if config.linkProcessingMode != .deferredOnly {
                if let launchURL = launchOptions?[.url] as? URL,
                   !LinkUtils.isInfrastructureUrl(launchURL.absoluteString)
                {
                    StorageUtils.markFirstEntrance()
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
                    StorageUtils.markFirstEntrance()
                    Task {
                        let result = await processLink(universalURL.absoluteString, config: config)
                        completion(result)
                    }
                    return
                }

                if !activities.isEmpty {
                    StorageUtils.markFirstEntrance()
                    // UIApplicationDelegate will invoke continueUserActivity next.
                    returnEmpty()
                    return
                }
            }
            
            // 3. DEFERRED LINK CHECK
            if !StorageUtils.isFirstEntrance() {
                returnEmpty()
                return
            }
            
            StorageUtils.markFirstEntrance()
            
            Task {
                let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
                DetourNetwork.matchLink(config: config, fingerprint: fingerprint, linkType: .deferred) { [weak self] result in
                    Task { @MainActor in
                        guard let self else {
                            completion(result)
                            return
                        }

                        let filteredResult = self.filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
                        completion(filteredResult)
                    }
                }
            }
        }
    
}

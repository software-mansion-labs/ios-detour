import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()
    
    private var isSessionHandled = false
    private var analyticsMountToken: UUID?
    
    private init() {} // Private init to force use of 'shared'

    @discardableResult
    public func mountAnalytics(config: DetourConfig) -> UUID {
        if let analyticsMountToken {
            return analyticsMountToken
        }

        let token = DetourAnalytics.mount(config: config)
        analyticsMountToken = token
        return token
    }

    public func unmountAnalytics() {
        guard let token = analyticsMountToken else { return }
        DetourAnalytics.unmount(token)
        analyticsMountToken = nil
    }
    
    // Converts a URL into a DetourResult with a parsed route.
    public func processLink(_ url: URL) -> DetourResult {
        if LinkUtils.isInfrastructureUrl(url.absoluteString) {
            return .empty()
        }

        let linkType = LinkUtils.detectLinkType(from: url)
        let route = LinkUtils.extractRoute(from: url)
        return DetourResult(processed: true, link: url, route: route, linkType: linkType)
    }

    // Processes URL and optionally resolves web short-links when config is provided.
    public func processLink(_ url: URL, config: DetourConfig?) async -> DetourResult {
        await processLink(url.absoluteString, config: config)
    }

    // Converts a raw link string into a DetourResult with route and link type.
    // If config is provided, web short-links are resolved before parsing.
    public func processLink(_ rawLink: String, config: DetourConfig? = nil) async -> DetourResult {
        if LinkUtils.isInfrastructureUrl(rawLink) {
            return .empty()
        }

        if !LinkUtils.looksLikeUrl(rawLink) {
            let route = LinkUtils.extractRoute(from: rawLink)
            return DetourResult(processed: true, link: nil, route: route, linkType: nil)
        }

        let normalized = LinkUtils.normalizeRawLink(rawLink)
        guard let url = URL(string: normalized) else {
            let route = LinkUtils.extractRoute(from: rawLink)
            return DetourResult(processed: true, link: nil, route: route, linkType: .scheme)
        }

        let isWebUrl = url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        let pathSegments = url.path.split(separator: "/").map(String.init)
        let isSingleSegmentPath = pathSegments.count == 1 && !pathSegments[0].isEmpty

        if isWebUrl, isSingleSegmentPath, let config {
            if let resolvedUrl = await DetourNetwork.resolveShortLink(config: config, url: rawLink),
               resolvedUrl.absoluteString != normalized {
                return processLink(resolvedUrl)
            }
        }

        return processLink(url)
    }
    
    public func resolveInitialLink(
            config: DetourConfig,
            launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
            completion: @escaping @Sendable (DetourResult) -> Void
        ) {
            _ = mountAnalytics(config: config)
            
            func returnEmpty() { completion(.empty()) }
            
            if isSessionHandled { returnEmpty(); return }
            isSessionHandled = true
            
            
            // UNIVERSAL LINK (https://)
            // We just check if the "User Activity Dictionary" exists.
            if let activityDict = launchOptions?[.userActivityDictionary] as? [UIApplication.LaunchOptionsKey: Any],
               let activityType = activityDict[.userActivityType] as? String,
               activityType == NSUserActivityTypeBrowsingWeb {
                
                StorageUtils.markFirstEntrance()
                
                // Return empty. The system will call 'continueUserActivity' immediately after this returns.
                returnEmpty()
                return
            }
            
            // 3. DEFERRED LINK CHECK
            if !StorageUtils.isFirstEntrance() {
                returnEmpty()
                return
            }
            
            StorageUtils.markFirstEntrance()
            
            Task {
                let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
                DetourNetwork.matchLink(config: config, fingerprint: fingerprint, linkType: .deferred, completion: completion)
            }
        }
    
}

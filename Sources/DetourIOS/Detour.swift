import Foundation
import UIKit


@MainActor
public class Detour {
    public static let shared = Detour()
    
    private var config: DetourConfig?
    private var isSessionHandled = false
    
    private init() {} // Private init to force use of 'shared'
    
    // Converts a raw URL into a DetourResult with a parsed route.
    public func processLink(_ url: URL) -> DetourResult {
        
        let route = LinkUtils.extractRoute(from: url)
        return DetourResult(processed: true, link: url, route: route)
    }
    
    public func resolveInitialLink(
            config: DetourConfig,
            launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
            completion: @escaping @Sendable (DetourResult) -> Void
        ) {
            self.config = config
            
            func returnEmpty() { DispatchQueue.main.async { completion(.empty()) } }
            
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
                DetourNetwork.matchLink(config: config, fingerprint: fingerprint, completion: completion)
            }
        }
    

    
}

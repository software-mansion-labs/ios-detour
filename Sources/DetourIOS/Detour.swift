

import Foundation
import UIKit

@MainActor
public class Detour {
    public static let shared = Detour()
    
    private var config: DetourConfig?
    private var isSessionHandled = false
    
    private let apiUrl = URL(string: "https://godetour.dev/api/link/match-link")!

    private init() {} // Private init to force use of 'shared'

    public func identify(config: DetourConfig, completion: @escaping @Sendable (DetourResult) -> Void) {
        self.config = config
        
        
        if isSessionHandled {
            DispatchQueue.main.async {
                completion(DetourResult.empty())
            }
            return
        }
        isSessionHandled = true
        
        
        if !StorageUtils.isFirstEntrance() {
            print("[Detour]:Not first entrance")
            DispatchQueue.main.async {
                completion(DetourResult.empty())
            }
            return
        }
        
        StorageUtils.markFirstEntrance()
        
        
        let fingerprint = DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
        
        DetourNetwork.matchLink(config: config, fingerprint: fingerprint, completion: completion)
    }
        
}

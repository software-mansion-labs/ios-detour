import Foundation
import UIKit

@MainActor
public class Detour {
    public static let shared = Detour()

    private var config: DetourConfig?
    private var isSessionHandled = false

    private let apiUrl = URL(string: "https://godetour.dev/api/link/match-link")!

    private init() {} // Private init to force use of 'shared'

    public func identify(
        config: DetourConfig,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        self.config = config

        if isSessionHandled {
            DispatchQueue.main.async {
                completion(DetourResult.empty())
            }
            return
        }
        isSessionHandled = true
        
        
        if let connectionOptions = launchOptions?[.url] as? URL {
            print("🔗 [Detour] Found Initial Universal Link: \(connectionOptions)")
            
            StorageUtils.markFirstEntrance()
            
            let extractedRoute = LinkUtils.extractRoute(from: connectionOptions)
            let result = DetourResult(
                processed: true,
                link: connectionOptions,
                route: extractedRoute
            )
            DispatchQueue.main.async { completion(result) }
            return
        }
        

        if !StorageUtils.isFirstEntrance() {
            print("[Detour]:Not first entrance")
            DispatchQueue.main.async {
                completion(DetourResult.empty())
            }
            return
        }

        StorageUtils.markFirstEntrance()

        Task {
            let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
            
            DetourNetwork.matchLink(config: config, fingerprint: fingerprint, completion: completion)
        }
    }
}

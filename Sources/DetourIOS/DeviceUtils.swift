import UIKit
import WebKit

class DeviceUtils {
    
    @MainActor
    private static var webView: WKWebView?
        
        @MainActor
        private static func getRealUserAgent() async -> String {
            return await withCheckedContinuation { continuation in
                
                webView = WKWebView()
                
                webView?.evaluateJavaScript("navigator.userAgent") { result, error in
                    
                    if let error = error {
                        print("⚠️ [Detour] WebKit Error: \(error.localizedDescription)")
                    }

                    if let ua = result as? String {
                        continuation.resume(returning: ua)
                    } else {
                        print("⚠️ [Detour] Could not retrieve WebKit User Agent. Result was nil.")
                        continuation.resume(returning: "")
                    }
                    
                    webView = nil
                }
            }
        }
    
    @MainActor
    static func getFingerprint(shouldUseClipboard: Bool) async -> ProbabilisticFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main

        var pastedLink: String?
        if shouldUseClipboard {
            let clipboardContent = await MainActor.run {
                UIPasteboard.general.string
            }
            
            // VALIDATION: Only accept if it's a valid web URL
            if let content = clipboardContent,
               let url = URL(string: content),
               let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()),
               url.host != nil {
                
                pastedLink = content
            }
        }

        let locales = Locale.preferredLanguages.map { LocaleTag(languageTag: $0) }
        
        let userAgent = await getRealUserAgent()

        return ProbabilisticFingerprint(
            platform: "ios",
            model: device.model,
            manufacturer: "Apple",
            systemVersion: device.systemVersion,
            screenWidth: Double(screen.bounds.width),
            screenHeight: Double(screen.bounds.height),
            scale: Double(screen.scale),
            locale: locales,
            timezone: TimeZone.current.identifier,
            userAgent: userAgent,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            pastedLink: pastedLink
        )
    }
}

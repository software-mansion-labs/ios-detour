

import UIKit

class DeviceUtils {
    
    static func getFingerprint(shouldUseClipboard: Bool) -> ProbabilisticFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main
        
        // Handling Clipboard (UIPasteboard)
        var pastedLink: String? = nil
        if shouldUseClipboard && UIPasteboard.general.hasStrings {
            pastedLink = UIPasteboard.general.string
        }

        // Handling Locales
        let locales = Locale.preferredLanguages.map { LocaleTag(languageTag: $0) }
        
        return ProbabilisticFingerprint(
            platform: "ios", // Platform.OS
            model: device.model, // Simple model name. specific model identifiers require more code
            manufacturer: "Apple",
            systemVersion: device.systemVersion,
            screenWidth: Double(screen.bounds.width),
            screenHeight: Double(screen.bounds.height),
            scale: Double(screen.scale),
            locale: locales,
            timezone: TimeZone.current.identifier,
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS \(device.systemVersion.replacingOccurrences(of: ".", with: "_")) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", // Simplified UA
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            pastedLink: pastedLink
        )
    }
}

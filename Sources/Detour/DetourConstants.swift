// CONTRACT: The Flutter plugin (detour-flutter-plugin) ships a marker class
// at exactly "DetourFlutterMarker" with a static property exposed to ObjC as
// "sdkHeaderValue". If either name changes, this lookup silently fails and
// Flutter apps will be reported as native iOS.
// Counterpart: detour-flutter-plugin/ios/Classes/DetourFlutterMarker.swift

import Foundation

enum DetourConstants {
    static let sdkType = "ios"
    static let flutterMarkerClassName = "DetourFlutterMarker"
    static let flutterSdkHeaderSelector = NSSelectorFromString("sdkHeaderValue")
    // Keep the native SDK version explicit because static linking can place Detour types
    // in the host app bundle, making bundle-based version lookup return the app version.
    static let sdkVersion = "1.0.2"
    static let sdkHeaderField = "X-SDK"
    static let sdkHeaderValue: String = {
        if let markerClass = NSClassFromString(flutterMarkerClassName) as? NSObject.Type,
           markerClass.responds(to: flutterSdkHeaderSelector),
           let value = markerClass.perform(flutterSdkHeaderSelector)?.takeUnretainedValue() as? String {
            // Flutter wrapper exposes the final header value directly to avoid static-lib bundle issues.
            return value
        }

        // Fallback for pure native iOS SDK consumers.
        return "\(sdkType)/\(sdkVersion)"
    }()
    static let apiUrl: URL? = URL(string: "https://godetour.dev/api/link/match-link")
    static let resolveShortUrl: URL? = URL(string: "https://godetour.dev/api/link/resolve-short")
    static let analyticsEventUrl: URL? = URL(string: "https://godetour.dev/api/analytics/event")
    static let analyticsRetentionUrl: URL? = URL(string: "https://godetour.dev/api/analytics/retention")
}

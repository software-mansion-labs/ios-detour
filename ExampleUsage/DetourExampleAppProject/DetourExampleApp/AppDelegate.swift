import UIKit
import SwiftUI
import DetourIOS
import os

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let logger = Logger(subsystem: "<YOUR_BUNDLE_IDENTIFIER>", category: "AppDelegate")

    private let detourConfig = DetourConfig(
        apiKey: "<YOUR_DETOUR_API_KEY>",
        appId: "<YOUR_DETOUR_APP_ID>",
        shouldUseClipboard: false
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(
            rootView: ContentView()
        )
        window.makeKeyAndVisible()
        self.window = window

        // Mount analytics once at startup.
        _ = Detour.shared.mountAnalytics(config: detourConfig)

        // Resolve initial deferred/universal link.
        Detour.shared.resolveInitialLink(config: detourConfig, launchOptions: launchOptions) { result in
            if let route = result.route {
                self.logger.info("Initial route: \(route)")
            } else {
                self.logger.info("No initial route")
            }

            Task { @MainActor in
                DetourDemoState.shared.markInitialLinkResolved()
                DetourDemoState.shared.recordLinkResult(result, source: "cold_start")
            }
        }

        return true
    }

    // Custom scheme, e.g. <YOUR_CUSTOM_SCHEME>://product/42
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let result = Detour.shared.processLink(url)

        Task { @MainActor in
            DetourDemoState.shared.recordLinkResult(result, source: "custom_scheme")
        }

        return true
    }

    // Universal links, e.g. https://<YOUR_UNIVERSAL_LINK_DOMAIN>/promo/offer
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }

        let result = Detour.shared.processLink(url)

        Task { @MainActor in
            DetourDemoState.shared.recordLinkResult(result, source: "universal_link")
        }

        return true
    }
}

import UIKit
import SwiftUI
import Detour
import os

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let logger = Logger(subsystem: "<YOUR_BUNDLE_IDENTIFIER>", category: "SceneDelegate")

    private let detourConfig = DetourConfig(
        apiKey: "<YOUR_DETOUR_API_KEY>",
        appID: "<YOUR_DETOUR_APP_ID>",
        shouldUseClipboard: false,
        linkProcessingMode: .all
    )

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: ContentView(title: "Detour UIKit Example")
        )
        window.makeKeyAndVisible()
        self.window = window

        // On a cold start, iOS passes the link that opened the app only here, not to the callbacks below.
        // Without such a link, the completion returns the deferred link.
        Detour.shared.resolveInitialLink(config: detourConfig, connectionOptions: connectionOptions) { result in
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
    }

    // Custom scheme, e.g. <YOUR_CUSTOM_SCHEME>://product/42
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        Task { @MainActor in
            let result = await Detour.shared.processLink(url, config: detourConfig)
            DetourDemoState.shared.recordLinkResult(result, source: "custom_scheme")
        }
    }

    // Universal links, e.g. https://<YOUR_UNIVERSAL_LINK_DOMAIN>/promo/offer
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }

        Task { @MainActor in
            let result = await Detour.shared.processLink(url, config: detourConfig)
            DetourDemoState.shared.recordLinkResult(result, source: "universal_link")
        }
    }
}

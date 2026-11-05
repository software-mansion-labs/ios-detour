import UIKit
import Detour

// A SwiftUI app has no connectionOptions, so the link that opened it arrives in .onOpenURL.
// This call only resolves the deferred link.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Detour.shared.resolveInitialLink(config: .example, launchOptions: launchOptions) { result in
            Task { @MainActor in
                DetourDemoState.shared.markInitialLinkResolved()
                DetourDemoState.shared.recordLinkResult(result, source: "deferred")
            }
        }

        return true
    }
}

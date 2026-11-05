import SwiftUI
import Detour

@main
struct DetourSwiftUIExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(title: "Detour SwiftUI Example")
                // SwiftUI passes custom scheme links and Universal Links here, including the link that opened the app.
                // It does not pass Universal Links to .onContinueUserActivity.
                .onOpenURL { url in
                    Task {
                        let result = await Detour.shared.processLink(url, config: .example)
                        DetourDemoState.shared.recordLinkResult(result, source: "open_url")
                    }
                }
        }
    }
}

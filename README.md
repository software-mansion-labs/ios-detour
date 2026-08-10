<img src="https://github.com/user-attachments/assets/c965b51b-7307-477a-8d22-9c9cd6da6231" alt="Detour iOS SDK by Software Mansion" width="100%"/>

[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-1?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-1&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-2?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-2&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-3?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-3&n=1)

# Detour iOS SDK

Detour is an iOS SDK for handling deferred deep links. A deferred link works like a regular deep link, but survives the App Store install — a user who clicks a link before having the app installed is redirected to the right screen on first launch. Detour also handles Universal Links and custom scheme links in a single unified API.

## Quick links

- Documentation: [https://detour.swmansion.com/docs/](https://detour.swmansion.com/docs/)
- Installation guide: [https://detour.swmansion.com/docs/sdk/ios/sdk-installation](https://detour.swmansion.com/docs/sdk/ios/sdk-installation)

## Create an account

You need a Detour account to generate app credentials and configure your links.  
Sign up here: [https://godetour.dev/auth/signup](https://godetour.dev/auth/signup)

## Installation

Latest stable release: `1.1.1`

### Requirements

- iOS 13.0+
- Swift 5.5+

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `Detour` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/software-mansion-labs/ios-detour", from: "1.1.1")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'Detour', '1.1.1'
end
```

Then run `pod install`.

## Usage

### 1. Configure

```swift
import Detour

let config = DetourConfig(
    apiKey: "<YOUR_DETOUR_API_KEY>",
    appID: "<YOUR_DETOUR_APP_ID>"
)
```

### 2. Resolve initial link on app launch

Call `resolveInitialLink` once on cold start. It also mounts analytics automatically, so no separate `mountAnalytics` call is needed.

AppDelegate:

<details>
<summary>AppDelegate example</summary>

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    Detour.shared.resolveInitialLink(config: config, launchOptions: launchOptions) { result in
        if let link = result.link {
            // Navigate to link.route
        }
    }
    return true
}
```

</details>

SceneDelegate:

<details>
<summary>SceneDelegate example</summary>

```swift
func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
) {
    Detour.shared.resolveInitialLink(config: config, connectionOptions: connectionOptions) { result in
        if let link = result.link {
            // Navigate to link.route
        }
    }
}
```

</details>

### 3. Handle runtime links

Handle custom scheme and Universal Links that arrive while the app is running:

<details>
<summary>Custom scheme</summary>

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    Task {
        let result = await Detour.shared.processLink(url, config: config)
        // handle result.link
    }
    return true
}
```

</details>

<details>
<summary>Universal Link</summary>

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return false }
    Task {
        let result = await Detour.shared.processLink(url, config: config)
        // handle result.link
    }
    return true
}
```

</details>

### Controlling which links Detour processes

Use `linkProcessingMode` to control which link sources the SDK handles:

| Value               | Universal links | Deferred links | Custom scheme links |
| ------------------- | --------------- | -------------- | ------------------- |
| `.all` (default)    | ✅              | ✅             | ✅                  |
| `.webOnly`          | ✅              | ✅             | ❌                  |
| `.deferredOnly`     | ❌              | ✅             | ❌                  |

<details>
<summary>linkProcessingMode config example</summary>

```swift
let config = DetourConfig(
    apiKey: "<YOUR_DETOUR_API_KEY>",
    appID: "<YOUR_DETOUR_APP_ID>",
    linkProcessingMode: .webOnly
)
```

</details>

## Analytics

Analytics are mounted automatically when you call `resolveInitialLink`. To log custom events use the predefined `DetourEventName` enum or a custom string:

<details>
<summary>Analytics example</summary>

```swift
DetourAnalytics.logEvent(.addToCart, data: ["sku": "abc"])
DetourAnalytics.logEvent("custom_event", data: ["source": "home"])
DetourAnalytics.logRetention("week_1")
```

</details>

If you need analytics without calling `resolveInitialLink`, mount and unmount manually:

```swift
Detour.shared.mountAnalytics(config: config)
// ...
Detour.shared.unmountAnalytics()
```

See the [analytics docs](https://detour.swmansion.com/docs/) for the full event list and retention tracking setup.

## Types

### DetourConfig

<details>
<summary>DetourConfig</summary>

```swift
public struct DetourConfig {
    public let apiKey: String
    public let appID: String
    public let shouldUseClipboard: Bool       // default: true
    public let linkProcessingMode: LinkProcessingMode  // default: .all
}
```

</details>

### DetourResult

<details>
<summary>DetourResult</summary>

```swift
public struct DetourResult {
    public let processed: Bool
    public let link: DetourLink?

    // Convenience accessors
    public var route: String?
    public var linkType: LinkType?
    public var pathname: String?
    public var params: [String: String]
    public var linkURL: URL?
}
```

</details>

### DetourLink

<details>
<summary>DetourLink</summary>

```swift
public struct DetourLink {
    public let url: String
    public let route: String
    public let pathname: String
    public let params: [String: String]
    public let type: LinkType
}
```

</details>

### LinkType

<details>
<summary>LinkType</summary>

```swift
public enum LinkType: String {
    case deferred   // User clicked link before app was installed
    case verified   // Universal Link — http/https with verified domain ownership
    case scheme     // Custom scheme deep link (e.g. myapp://...)
}
```

</details>

### LinkProcessingMode

<details>
<summary>LinkProcessingMode</summary>

```swift
public enum LinkProcessingMode: String {
    case all
    case webOnly
    case deferredOnly
}
```

</details>

## Example project

A ready-to-run example covering deferred links, Universal Links, and custom scheme links is included at [`ExampleUsage/DetourExampleAppProject`](./ExampleUsage/DetourExampleAppProject). See the [example setup guide](./ExampleUsage/README.md) for instructions.

## Privacy

Detour bundles a `PrivacyInfo.xcprivacy` manifest, copied into your app by both Swift Package Manager and CocoaPods, so you do not need to work out its API usage or data collection yourself. It declares Detour as non-tracking (`NSPrivacyTracking = false`, no tracking domains), so no App Tracking Transparency prompt is required. You **do** still need to reflect what Detour collects in your App Store Connect privacy questionnaire — Apple requires the app developer to declare everything the app collects, including via SDKs.

<details>
<summary>What the manifest declares</summary>

| Declared | Details |
| --- | --- |
| `UserDefaults` API, reason `CA92.1` | Own app-scoped keys only: a first-launch flag and a locally generated device ID. |
| `DeviceID` | Random UUID stored on device, sent with analytics events. |
| `ProductInteraction` | Event names from `logEvent` / `logRetention`, plus universal-link opens (link URL, its query parameters, app version, OS version, device model). |
| `OtherUserContent` | A web URL extracted from the clipboard, read on first launch (and again after `resetSession(allowDeferredRetry: true)`). Only the URL is sent — any text copied along with it is discarded on device, and a clipboard holding no web URL sends nothing. Not read at all when `shouldUseClipboard: false`. |
| `OtherDataTypes` | Deferred-matching fingerprint, sent on first launch (and again after `resetSession(allowDeferredRetry: true)`): device model, OS version, screen size and scale, locales, timezone, user agent. |

Every collected type is declared as not linked to the user and not used for tracking. Xcode includes the manifest in the Privacy Report it generates when you archive (Xcode → Organizer → right-click your archive → *Generate Privacy Report*).

</details>

<details>
<summary>Clipboard access shows a system paste alert</summary>

When the copied content came from another app, iOS presents its own paste-permission modal (`"YourApp" would like to paste from "Safari"`) before your UI appears on first launch, and its default button denies. Detour checks `detectPatterns(for: [.probableWebURL])` first, so the read only happens when the clipboard actually holds a web URL — but that check does not suppress the alert. Set `shouldUseClipboard: false` to skip the read entirely and never show it; deferred matching then runs without the clipboard signal.

</details>

<details>
<summary>What to answer in App Store Connect</summary>

In App Store Connect, go to your app → **App Privacy** → **Data Types** → **Edit**, and answer **Yes** to "Do you or your third-party partners collect data from this app?".

**Step 1 — tick the applicable boxes.** They're listed here in the order they appear on screen, so you can work top to bottom:

| Category | Tick | Applies when |
| --- | --- | --- |
| **User Content** → Other User Content | Yes | Only if you leave `shouldUseClipboard` enabled (the default). Skip it if you set `shouldUseClipboard: false`. |
| **Identifiers** → Device ID | Yes | Always — Detour generates and stores a random device ID for analytics. |
| **Usage Data** → Product Interaction | Yes | Always — event names from `logEvent` / `logRetention`, plus universal-link opens. |
| **Other Data** → Other Data Types | Yes | Always — the deferred-matching fingerprint. |

**Step 2 — fill in the section for each box you ticked.** Once you save, App Store Connect adds a dedicated section per data type further down the page. Click **Set Up Other User Content**, **Set Up Device ID**, and so on, and answer the three questions in each:

| Data type | "Used for" (select all that apply) | "Linked to identity" | "Used for tracking" |
| --- | --- | --- | --- |
| Other User Content | App Functionality | No | No |
| Device ID | App Functionality, Analytics | No | No |
| Product Interaction | App Functionality, Analytics | No | No |
| Other Data Types | App Functionality | No | No |

These answers mirror [`Sources/Detour/Resources/PrivacyInfo.xcprivacy`](./Sources/Detour/Resources/PrivacyInfo.xcprivacy) exactly, so you can cross-check them against the Privacy Report Xcode generates from your archive.

Two things to double-check for your own app on top of this:

- Detour cannot see what you pass in `DetourAnalytics.logEvent(_:data:)`. If you put personal data there, declare it yourself.
- Universal-link query parameters are forwarded to Detour as-is. If your links carry personal data in params, that's yours to declare too.

</details>

## Other Detour SDKs

Detour is also available for other app stacks:

- Android SDK: [https://github.com/software-mansion-labs/android-detour](https://github.com/software-mansion-labs/android-detour)
- Flutter SDK: [https://github.com/software-mansion-labs/detour-flutter-plugin](https://github.com/software-mansion-labs/detour-flutter-plugin)
- React Native SDK: [https://github.com/software-mansion-labs/react-native-detour](https://github.com/software-mansion-labs/react-native-detour)

---

## License

This library is licensed under [The MIT License](./LICENSE).

## Detour iOS SDK is created by Software Mansion

Since 2012, [Software Mansion](https://swmansion.com) is a software agency with experience in building web and mobile apps. We are Core React Native Contributors and experts in dealing with all kinds of React Native issues. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects?utm_source=detour&utm_medium=readme).

[![swm](https://logo.swmansion.com/logo?color=white&variant=desktop&width=150&tag=ios-detour-github "Software Mansion")](https://swmansion.com)

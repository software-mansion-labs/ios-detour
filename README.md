<img src="https://github.com/user-attachments/assets/c965b51b-7307-477a-8d22-9c9cd6da6231" alt="Detour iOS SDK by Software Mansion" width="100%"/>

[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-1?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-1&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-2?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-2&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-ios-detour-3?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-ios-detour-3&n=1)

# Detour iOS SDK

Detour is an iOS SDK for handling deferred deep links. A deferred link works like a regular deep link, but survives the App Store install — a user who clicks a link before having the app installed is redirected to the right screen on first launch. Detour also handles Universal Links and custom scheme links in a single unified API.

## Quick links

- Documentation: [https://detour.swmansion.com/docs/](https://detour.swmansion.com/docs/)
- Installation guide: [https://detour.swmansion.com/docs/sdk/ios/sdk-installation](https://detour.swmansion.com/docs/sdk/ios/sdk-installation)

## Create an account

You need a Detour account to generate app credentials and configure your links.  
Sign up here: [https://godetour.dev/auth/signup](https://godetour.dev/auth/signup)

## Installation

Latest stable release: `1.1.0`

### Requirements

- iOS 13.0+
- Swift 5.5+

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `Detour` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/software-mansion-labs/ios-detour", from: "1.1.0")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'Detour', '1.1.0'
end
```

Then run `pod install`.

Either integration path bundles Detour's [privacy manifest](#privacy) automatically — there is nothing to add to your app's own `PrivacyInfo.xcprivacy`.

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

## Privacy

Detour ships a `PrivacyInfo.xcprivacy` privacy manifest inside the SDK. Xcode bundles it automatically for both Swift Package Manager and CocoaPods, and Apple aggregates it into your app's Privacy Report at upload time — you do not need to declare Detour's API usage or data collection in your own app-level manifest.

Detour does not track users: the manifest declares `NSPrivacyTracking = false` with no tracking domains. Nothing Detour collects is linked to a user's identity, combined with third-party data for advertising, or shared with data brokers.

### What the manifest declares

**Required reason APIs**

| API category | Reason | Why |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Detour reads and writes only its own app-scoped keys — a first-launch flag for deferred link matching, and a locally generated analytics device ID. |

**Collected data** — all entries are declared as not linked to the user and not used for tracking.

| Data type | Purpose | What it covers |
| --- | --- | --- |
| `NSPrivacyCollectedDataTypeDeviceID` | App Functionality, Analytics | A random UUID generated on device and stored in `UserDefaults`, sent with analytics events so repeat events can be deduplicated and retention measured. It is not the IDFA or IDFV, and is discarded when the app is uninstalled. Also covers the device model and OS version sent with universal link clicks. |
| `NSPrivacyCollectedDataTypeProductInteraction` | Analytics, App Functionality | Event names sent by `DetourAnalytics.logEvent` / `logRetention`, plus link clicks. |
| `NSPrivacyCollectedDataTypeOtherUserContent` | App Functionality | The clipboard string, read once on first launch and only when it looks like a web URL, to match a deferred link. Not collected when you set `shouldUseClipboard: false`. |
| `NSPrivacyCollectedDataTypeOtherDataTypes` | App Functionality | The probabilistic fingerprint used for deferred link matching on first launch: device model, OS version, screen dimensions and scale, preferred locales, timezone, and browser user agent. Apple has no dedicated category for these device attributes. |

The fingerprint is sent once, on first launch only. The matching endpoint returns a single link, which the SDK uses to route the user to the right screen. As of this version it does not feed advertising or ad measurement, which is why Detour is declared as non-tracking and requires no App Tracking Transparency prompt.

### App Store Connect privacy questionnaire

Answer the "nutrition label" questions below for the data Detour collects, on top of whatever your own app collects. For every entry, answer **No** to "Are these data used to track you?" and **Not linked to the user's identity** — unless your own app's use of the same data type says otherwise, in which case the stricter answer wins.

| Question | Answer |
| --- | --- |
| Identifiers → **Device ID** | Yes — App Functionality, Analytics |
| Usage Data → **Product Interaction** | Yes — Analytics, App Functionality |
| User Content → **Other User Content** | Yes — App Functionality *(skip if you set `shouldUseClipboard: false`)* |
| Diagnostics / **Other Data** | Yes — App Functionality |

Two things to check against your own configuration:

- **If you set `shouldUseClipboard: false`**, Detour never reads the clipboard, and you can leave User Content out of your App Store Connect answers. The bundled manifest still lists it, because a manifest is static and the option defaults to `true`; the manifest and your questionnaire answers are evaluated separately, so declaring less in App Store Connect than the SDK manifest lists is fine when the SDK genuinely does not collect it in your configuration.
- **Custom event payloads are yours to declare.** Detour cannot know what you pass in `DetourAnalytics.logEvent(_:data:)`. If you put emails, names, purchase amounts, or any other personal data in that dictionary, declare those data types yourself.

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

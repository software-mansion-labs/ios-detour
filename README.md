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

Latest stable release: `1.1.2`

### Requirements

- iOS 15.0+
- Swift 5.5+

### Swift Package Manager

In Xcode, go to `File > Add Package Dependencies...`, enter the repository URL, and add `Detour` to your app target. For [attribution](#attribution), add `DetourAttribution` too; an app with `Detour` alone links no attribution framework.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/software-mansion-labs/ios-detour", from: "1.1.2")
```

### CocoaPods

In your `Podfile`:

```ruby
platform :ios, '15.0'

target 'YourAppTarget' do
  use_frameworks!
  pod 'Detour', '1.1.2'
  pod 'DetourAttribution', '1.1.2' # only for attribution
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

### Starting only after consent

`resolveInitialLink` configures and starts the SDK in one call. To wait for consent, `setConsent` is usually enough: analytics follows the consent gate described below, and with attribution on the first deferred link match waits for the choice on `attribution`. Split the call only if the law that applies to you requires consent before anything else leaves the device, deferred link matching included: `configure` sets the SDK up, and `start` begins analytics, sessions and deferred link matching. Events and conversions you log before `start` are kept in memory (up to 100) and sent after it, if consent to `analytics` allows. Links the user taps before `start` are routed and counted: the SDK sends the link click (link URL, app version, OS version, device model), because your plan's click limit applies to it.

When the deferred link waits for `start` or for consent, the `resolveInitialLink` completion comes only after it. If your app holds its UI until the initial link is handled, wait for `onReadyForUI` instead: it is called once, before the completion or before the SDK starts waiting, so you can show your consent prompt. A deferred link found after that still arrives in the completion.

```swift
Detour.shared.configure(config, autoStart: false)
Detour.shared.resolveInitialLink(
    config: config,
    launchOptions: launchOptions,
    onReadyForUI: { showFirstScreen() }
) { result in
    // handle result.link
}

// after your consent platform has the user's choice
Detour.shared.start()
```

To pass the user's choice per purpose, call `setConsent` on every launch once your consent platform has it. The call is cheap: without a `timestamp`, a choice the Detour server already has is not sent again. Purposes are strings (`DetourPurpose.analytics` and others), and a purpose missing from the map is not granted. Detour sends analytics without a choice unless the Detour team has set your app to wait for one; a refusal stops analytics at once, also on the next launch before you call `setConsent` again. Deferred link matching does not depend on this choice, except with attribution on: then the first match waits for the choice on `attribution`. If your users' consent is needed for the match itself, call `start` only after it.

```swift
Detour.shared.setConsent(
    DetourConsent(
        purposes: [DetourPurpose.analytics: true, DetourPurpose.adNetworkSharing: false],
        consentTextRef: "cmp-v12",
        source: "cmp"
    ),
    consentText: noticeText
)
```

To turn the SDK off for a user, call `setEnabled(false)`. It stays off across launches until `setEnabled(true)`. While off, the SDK sends nothing (analytics, sessions, conversions, consent, deferred link matching); links the user taps are still routed. Withdrawing consent for a purpose stops only that purpose.

```swift
Detour.shared.setEnabled(false)
```

To check your consent integration, call `getStatus()`. It tells whether the SDK has started, whether it is on, whether `setConsent` was called on this launch, and for each purpose the consent gate's decision (`.send`, `.wait` or `.drop`). Before `start()` requests wait anyway. In debug builds the SDK also logs a warning once per launch when `setConsent` came but `start()` did not, when the purposes have no `analytics` key, when analytics waits because no consent was passed on this launch, and when a consent from an earlier launch was not passed again.

```swift
let status = Detour.shared.getStatus()
// isStarted: true, isEnabled: true, hasConsentThisLaunch: true, purposes: ["analytics": .send, "attribution": .drop, ...]
```

### Consent at a glance

Pass the user's choice on every launch, as soon as your consent platform has it:

```swift
// cmp is your consent platform.
Detour.shared.configure(config, attribution: DetourAttribution())
Detour.shared.resolveInitialLink(
    config: config,
    launchOptions: launchOptions,
    onReadyForUI: { showFirstScreen() }
) { result in
    // handle result.link
}

cmp.onChoice { choice in
    Detour.shared.setConsent(DetourConsent(
        purposes: [
            DetourPurpose.analytics: choice.analytics,
            DetourPurpose.attribution: choice.marketing,
            DetourPurpose.adNetworkSharing: choice.marketing,
            DetourPurpose.adPersonalization: choice.marketing,
        ],
        timestamp: choice.decidedAt
    ))
}
```

The table shows what happens to each request in each state. A request goes out only when every switch lets it through. Events and conversions follow the `DetourPurpose.analytics` purpose, attribution data the `DetourPurpose.attribution` purpose. The Detour backend sends data to ad networks only with consent to `DetourPurpose.adNetworkSharing`, and to Google only with `DetourPurpose.adPersonalization` too, so pass both when your prompt asks for them. Without a choice on this launch, the gate from the Detour server config decides: `open` sends, `closed` waits. On a first launch every gate waits until that config arrives.

| Request | Before `start()` | No choice yet, gate `closed` | Purpose refused | `setEnabled(false)` |
| --- | --- | --- | --- | --- |
| Deferred link match | Waits | Sent. With attribution on, waits for the choice on `DetourPurpose.attribution` | Sent (as `core` if `DetourPurpose.attribution` is refused) | Dropped. On Android a click ID from the Play install referrer still matches, without device data |
| Click on a link the user taps | Sent | Sent | Sent | Dropped; the link is still routed |
| `app_open` and sessions | Start with `start()` | Wait in memory (up to 100) | Dropped | Dropped |
| Your events and conversions | Wait in memory (up to 100) | Wait in memory (up to 100) | Dropped | Dropped |
| Attribution data (`X-SDK-Package: mmp`, Apple Search Ads token, SKAdNetwork values, Meta Install Referrer) | Wait | Wait | Not sent; requests go as `core` | Not sent |
| Consent record from `setConsent` | Sent | Sent | Sent | Not sent |

`start()` matters only if you turned the automatic start off (`autoStart: false`), which only a law that requires consent for deferred link matching asks for. `DetourAttribution()` comes from the `DetourAttribution` product; leave it out if you do not use attribution. Check what the SDK does at any moment with `Detour.shared.getStatus()`.

### Attribution

The `DetourAttribution` product attributes installs and conversions to your ad campaigns. Pass it to `configure`:

```swift
import Detour
import DetourAttribution

Detour.shared.configure(config, attribution: DetourAttribution())
Detour.shared.resolveInitialLink(
    config: config,
    launchOptions: launchOptions,
    onReadyForUI: { showFirstScreen() }
) { result in
    // handle result.link
}

// after your consent platform has the user's choice
Detour.shared.setConsent(DetourConsent(purposes: [
    DetourPurpose.analytics: true,
    DetourPurpose.attribution: true,
    DetourPurpose.adNetworkSharing: true,
    DetourPurpose.adPersonalization: true,
]))
```

Everything below happens only while the user's consent to `DetourPurpose.attribution` is passed on this launch. Without it, deferred links, analytics and conversions work as without the product, and nothing is attributed to a campaign.

- Requests feed attribution of the install to the ad network click it came from.
- `DetourAnalytics.logConversion` sets the SKAdNetwork conversion value, and from iOS 17.4 the AdAttributionKit one too. The rules that map a conversion to a value come from the Detour server, so changing them needs no app update. The SDK sends only increases: the highest matching value wins.
- The first deferred link request carries the Apple Search Ads attribution token, so an install from a Search Ads campaign is not counted as organic.

Sending data to ad networks needs one more purpose. The Detour backend sends an install or a conversion to a network set up for your app only with consent to `DetourPurpose.adNetworkSharing`; Google also needs `DetourPurpose.adPersonalization`. Without it the install is still attributed in Detour, but nothing goes to the network.

With consent to `DetourPurpose.adNetworkSharing` and tracking allowed in the App Tracking Transparency prompt, the SDK also sends the IDFA, so the ad network can match the install and later conversions to the user it showed the ad to. Detour never shows the prompt: request it yourself (`ATTrackingManager.requestTrackingAuthorization`, with `NSUserTrackingUsageDescription` in your `Info.plist`). When you ask after the first deferred link request, for example after onboarding, the SDK sends the IDFA as soon as the app is active again after the prompt. The SDK sends a change, or tells the backend to forget the IDFA, when the user turns tracking off or withdraws consent. In an app for children (App Store Kids category, COPPA) pass `DetourAttribution(isChildDirected: true)`: the SDK then reads no device identifier. Your consent prompt has to say this: that data is shared with ad networks (such as Google) and used to personalize ads. SKAdNetwork and AdAttributionKit postbacks are sent by Apple and follow `DetourPurpose.attribution` only.

With consent to `DetourPurpose.attribution`, the SDK can also send the IDFV (identifier for vendor), which helps recognize a user who reinstalls the app and goes to Meta as its vendor ID; it never goes to Google. It is off until the Detour team turns it on for your app. To keep it on the device in any case, pass `DetourAttribution(readsIDFV: false)`.

The install is attributed from the first deferred link request, and that request goes once per install. With attribution on, it waits until your app passes the user's choice: after consent to `attribution` it goes as `mmp`, after a refusal as `core`; if the attribution gate is open for your app in the Detour server config, it goes at once. An app closed before the choice still matches on its next launch. The completion of `resolveInitialLink` comes only after the choice, so use `onReadyForUI` to show your consent prompt (see Starting only after consent). Registration for SKAdNetwork also waits for the choice.

Your app needs no ad network identifiers for its installs to be attributed: `SKAdNetworkItems` belongs in apps that display ads, not in the app being advertised. Apple sends each winning postback to the ad network. To let Detour receive a copy of it, add both keys to your app's `Info.plist`:

```xml
<key>NSAdvertisingAttributionReportEndpoint</key>
<string>https://godetour.dev</string>
<key>AttributionCopyEndpoint</key>
<string>https://godetour.dev</string>
```

The first key is for SKAdNetwork, the second for AdAttributionKit (in Xcode: "AdAttributionKit - Postback Copy URL"). Each key takes one URL, so if another attribution provider already uses them, the copies go to only one of you. The SDK logs a warning at start when a key is missing.

> Detour does not process these copies yet. Adding the keys now means your next release does not need another `Info.plist` change.

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

To link events to your own user account, pass your user identifier after the user signs in, and `nil` after sign-out. A stable account ID: the same for the user on every install, never a guest or anonymous ID. Do not pass an e-mail address or a phone number. A value that is empty or longer than 256 characters (UTF-16 code units) is dropped and clears the stored one.

```swift
Detour.shared.setUserId("u_12345")
// ...
Detour.shared.setUserId(nil)
```

To report revenue, log a conversion. Use `.iap` for purchases and subscriptions and `.inAppAds` for ad revenue; pass the store's transaction ID so a repeated purchase is counted once. A `revenue` value in `logEvent` (any event name) does not count as revenue. A conversion with an invalid field (for example a currency that is not a three-letter ISO 4217 code) is not sent; the SDK logs a warning that names the field.

```swift
DetourAnalytics.logConversion(DetourConversion(
    name: "purchase",
    revenue: Decimal(string: "4.99")!,
    currency: "USD",
    revenueType: .iap,
    productId: "coins_500",
    quantity: 1,
    transactionId: transaction.id.description
))
```

Sessions are reported automatically while analytics is mounted.

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
    public let baseURL: URL?                  // default: nil (production Detour API)
    public let userIdValidator: (@Sendable (String) -> Bool)?  // default: nil
}
```

`userIdValidator` checks every `setUserId` value and the stored one once the config is passed to `configure`, `resolveInitialLink` or `mountAnalytics`; returning `false` drops the value and clears the stored one.

`baseURL` points the SDK at another Detour API host, for tests and non-production environments. Only `https` URLs are accepted; with any other scheme the SDK logs an error and sends no requests. When `baseURL` is set, the SDK logs a warning on first use so a test host does not end up in a production build.

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
| `UserDefaults` API, reason `CA92.1` | Own app-scoped keys only: the user ID set with `setUserId`. |
| `ProductInteraction` | Event names from `logEvent` / `logRetention`, plus universal-link opens (link URL, its query parameters, app version, OS version, device model). Sessions: once analytics is mounted, the start and end of each use of the app with its duration, under a random session ID kept in memory only; more than 30 minutes in the background starts a new session. Events and deferred matching also carry the app version and build number, OS version, network type (Wi-Fi, cellular, other), install source (App Store or sandbox) and the App Tracking Transparency status, which Detour only reads and never requests; events also carry the preferred language. |
| `OtherUserContent` | A web URL extracted from the clipboard, read on first launch (and again after `resetSession(allowDeferredRetry: true)`). Only the URL is sent — any text copied along with it is discarded on device, and a clipboard holding no web URL sends nothing. Not read at all when `shouldUseClipboard: false`. |
| `OtherDataTypes` | Deferred-matching signals, sent on first launch (and again after `resetSession(allowDeferredRetry: true)`): device model, OS version, screen size and scale, locales, timezone, user agent. |

Detour also sends a random install ID, generated on first launch, with deferred matching and analytics events. It is stored in a file excluded from backups, so a reinstall or a restored phone gets a new one. It identifies this installation of your app, not the device, so the manifest does not declare it as Device ID.

Every collected type is declared as not linked to the user and not used for tracking; if you call `setUserId`, see "What to answer in App Store Connect" below. Xcode includes the manifest in the Privacy Report it generates when you archive (Xcode → Organizer → right-click your archive → *Generate Privacy Report*).

</details>

<details>
<summary>With DetourAttribution</summary>

`DetourAttribution` has its own `PrivacyInfo.xcprivacy`, copied into your app only when you add the product. It declares `NSPrivacyTracking = true` with no tracking domains, so the Privacy Report of an app with it shows tracking. It sends the SKAdNetwork and AdAttributionKit conversion values to Apple and the Apple Search Ads token to Detour, and declares one data type of its own: Device ID (the IDFA and the IDFV), used for tracking, third-party advertising and analytics and not linked to the user. In App Store Connect tick **Identifiers** → Device ID (Third-Party Advertising and Analytics, used for tracking; linked to identity if you call `setUserId`). Detour never shows the App Tracking Transparency prompt; whether your app needs it depends on how it uses the data. The App Store Connect answers below cover Detour without this product: with attribution on, review them for how your app uses the data for its ad campaigns.

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
| **Usage Data** → Product Interaction | Yes | Always — event names from `logEvent` / `logRetention`, plus universal-link opens. |
| **Other Data** → Other Data Types | Yes | Always — the deferred-matching signals. |

**Step 2 — fill in the section for each box you ticked.** Once you save, App Store Connect adds a dedicated section per data type further down the page. Click **Set Up Other User Content**, **Set Up Product Interaction**, and so on, and answer the three questions in each:

| Data type | "Used for" (select all that apply) | "Linked to identity" | "Used for tracking" |
| --- | --- | --- | --- |
| Other User Content | App Functionality | No | No |
| Product Interaction | App Functionality, Analytics | No | No |
| Other Data Types | App Functionality | No | No |

These answers mirror [`Sources/Detour/Resources/PrivacyInfo.xcprivacy`](./Sources/Detour/Resources/PrivacyInfo.xcprivacy) exactly, so you can cross-check them against the Privacy Report Xcode generates from your archive.

Also check these for your own app:

- If you call `Detour.setUserId`, Detour sends your user ID with deferred matching, events, conversions and consent records. Tick **Identifiers** → User ID (App Functionality, Analytics), and answer "Linked to identity: Yes" for it and for every Detour data type above.
- Detour cannot see what you pass in `DetourAnalytics.logEvent(_:data:)`. If you put personal data there, declare it yourself.
- If you call `DetourAnalytics.logConversion`, Detour receives the name, revenue, currency, revenue type, product ID, quantity and transaction ID of each conversion. Declare **Purchases** → Purchase History for Analytics yourself (linked to identity if you call `setUserId`); the manifest does not include it.
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

<img src="https://github.com/user-attachments/assets/c965b51b-7307-477a-8d22-9c9cd6da6231" alt="IOS Detour by Software Mansion" width="100%"/>

[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-1?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-react-native-detour-1&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-2?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-react-native-detour-2&n=1)
[![Ad](https://revive-adserver.swmansion.com/www/images/zone-gh-react-native-detour-3?n=1)](https://revive-adserver.swmansion.com/www/delivery/ck.php?zoneid=zone-gh-react-native-detour-3&n=1)

# Detour iOS SDK

SDK for handling deferred links and deep links in native iOS apps.

## Create an account

You need a Detour account to generate app credentials and configure links.
Sign up here: [https://godetour.dev/auth/signup](https://godetour.dev/auth/signup)

## Other Detour SDKs

Detour is also available for other app stacks:

- Android SDK: [https://github.com/software-mansion-labs/android-detour](https://github.com/software-mansion-labs/android-detour)
- Flutter SDK: [https://github.com/software-mansion-labs/detour-flutter-plugin](https://github.com/software-mansion-labs/detour-flutter-plugin)
- React Native SDK: [https://github.com/software-mansion-labs/react-native-detour](https://github.com/software-mansion-labs/react-native-detour)

## Installation

### Swift Package Manager (SPM)

In Xcode:

1. Open your project.
2. Go to `File > Add Package Dependencies...`
3. Enter your `Detour` repository URL.
4. Add `Detour` to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/software-mansion-labs/ios-detour", from: "0.1.0")
```

## Usage

### 1. Import and configure

```swift
import Detour

let config = DetourConfig(
    apiKey: "<YOUR_DETOUR_API_KEY>",
    appID: "<YOUR_DETOUR_APP_ID>",
    shouldUseClipboard: true,
    linkProcessingMode: .all
)
```

### 2. Resolve initial link on app launch

```swift
Detour.shared.resolveInitialLink(config: config, launchOptions: launchOptions) { result in
    if let link = result.link {
        print("Route: \(link.route)")
        print("Type: \(link.type.rawValue)")
    }
}
```

### 3. Handle runtime links

Custom scheme:

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
) -> Bool {
    Task {
        let result = await Detour.shared.processLink(url, config: config)
        // handle result.link
    }
    return true
}
```

Universal link:

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
        return false
    }

    Task {
        let result = await Detour.shared.processLink(url, config: config)
        // handle result.link
    }
    return true
}
```

## Link Processing Mode

Use `linkProcessingMode` to control which links SDK handles:

| Value            | Universal links | Deferred links | Custom scheme links |
| ---------------- | --------------- | -------------- | ------------------- |
| `.all` (default) | Yes             | Yes            | Yes                 |
| `.webOnly`       | Yes             | Yes            | No                  |
| `.deferredOnly`  | No              | Yes            | No                  |

## Analytics

Mount once (for example on app startup):

```swift
Detour.shared.mountAnalytics(config: config)
```

Log events:

```swift
DetourAnalytics.logEvent(.addToCart, data: ["sku": "abc"])
DetourAnalytics.logEvent("custom_event", data: ["source": "home"])
DetourAnalytics.logRetention("app_open")
```

## Types

### DetourConfig

```swift
public struct DetourConfig {
    public let apiKey: String
    public let appID: String
    public let shouldUseClipboard: Bool
    public let linkProcessingMode: LinkProcessingMode
}
```

### LinkProcessingMode

```swift
public enum LinkProcessingMode: String {
    case all
    case webOnly
    case deferredOnly
}
```

### DetourResult

```swift
public struct DetourResult {
    public let processed: Bool
    public let link: DetourLink?

    public var route: String?
    public var linkType: LinkType?
    public var pathname: String?
    public var params: [String: String]
    public var linkURL: URL?
}
```

### DetourLink

```swift
public struct DetourLink {
    public let url: String
    public let route: String
    public let pathname: String
    public let params: [String: String]
    public let type: LinkType
}
```

### LinkType

```swift
public enum LinkType: String {
    case deferred
    case verified
    case scheme
}
```

## Example Project

A ready-to-run example is included at:

- `ExampleUsage/DetourExampleAppProject`

Setup guide:

- `ExampleUsage/README.md`

---

## License

This library is licensed under [The MIT License](./LICENSE).

## Detour is created by Software Mansion

Since 2012, [Software Mansion](https://swmansion.com) is a software agency with experience in building web and mobile apps. We are Core React Native Contributors and experts in dealing with all kinds of React Native issues. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects?utm_source=detour&utm_medium=readme).

[![swm](https://logo.swmansion.com/logo?color=white&variant=desktop&width=150&tag=react-native-executorch-github "Software Mansion")](https://swmansion.com)

# Detour iOS Examples

These examples demonstrate all three link types supported by the Detour SDK:

- **Deferred link** — resolved on first launch after install
- **Universal Link** — http/https link handled while the app is installed
- **Custom scheme link** — e.g. `myapp://product/42`

Both apps use the UIScene lifecycle, which apps built with the iOS 27 SDK need to launch on iOS 27. Pick the one that matches your app:

| Project                                                        | App lifecycle                |
| -------------------------------------------------------------- | ---------------------------- |
| [`DetourExampleAppProject`](./DetourExampleAppProject)         | UIKit with a `SceneDelegate` |
| [`DetourSwiftUIExampleProject`](./DetourSwiftUIExampleProject) | SwiftUI `App`                |

## UIKit with SceneDelegate

`Info.plist` declares the scene in `UIApplicationSceneManifest`, and `SceneDelegate.swift` passes every link to Detour:

| Method                            | Links                                                          |
| --------------------------------- | -------------------------------------------------------------- |
| `scene(_:willConnectTo:options:)` | The link that opened the app, or the deferred link without one |
| `scene(_:openURLContexts:)`       | Custom scheme links while the app runs                         |
| `scene(_:continue:)`              | Universal Links while the app runs                             |

## SwiftUI

A SwiftUI `App` uses scenes without a SceneDelegate, so it has no `connectionOptions`. The `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` build setting adds the scene manifest.

| Code                                                               | Links                                                                           |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `.onOpenURL` in `DetourSwiftUIExampleApp.swift`                    | Custom scheme links and Universal Links, including the link that opened the app |
| `resolveInitialLink(config:launchOptions:)` in `AppDelegate.swift` | The deferred link, unless a link opened the app during the deferred match       |

## Prerequisites

You need a Detour account with an app configured. Sign up at [godetour.dev](https://godetour.dev/auth/signup) if you haven't already.

## Setup

### 1. Open the project

Open the project in Xcode:

- UIKit: `DetourExampleAppProject/DetourExampleApp.xcodeproj`
- SwiftUI: `DetourSwiftUIExampleProject/DetourSwiftUIExample.xcodeproj`

### 2. Replace placeholders

The placeholders appear in these files:

- UIKit: `SceneDelegate.swift`, `Info.plist`, and `DetourExampleApp.entitlements`
- SwiftUI: `DetourExampleConfig.swift`, `Info.plist`, and `DetourSwiftUIExample.entitlements`

| Placeholder                    | Where to find it                        | Example value              |
| ------------------------------ | --------------------------------------- | -------------------------- |
| `<YOUR_DETOUR_API_KEY>`        | Detour dashboard → your app → API key   | `dtk_live_abc123`          |
| `<YOUR_DETOUR_APP_ID>`         | Detour dashboard → your app → App ID    | `app_xyz789`               |
| `<YOUR_BUNDLE_IDENTIFIER>`     | Xcode → target → General → Bundle ID   | `com.company.exampleapp`   |
| `<YOUR_CUSTOM_SCHEME>`         | Pick any scheme for your app            | `myapp`                    |
| `<YOUR_UNIVERSAL_LINK_DOMAIN>` | Detour dashboard → your app → domain   | `example.godetour.link`    |

### 3. Configure URL scheme

In `Info.plist`, replace `<YOUR_CUSTOM_SCHEME>` under `CFBundleURLSchemes` with your chosen scheme.

### 4. Configure Associated Domains

In the `.entitlements` file, replace `<YOUR_UNIVERSAL_LINK_DOMAIN>` under `Associated Domains` with your Detour domain (e.g. `applinks:example.godetour.link`).

### 5. Run

Select a simulator or device and press **Run** in Xcode.

## Testing

| Scenario        | How to trigger                                                             |
| --------------- | -------------------------------------------------------------------------- |
| Deferred link   | Create a link in the Detour dashboard, open it on a fresh install          |
| Universal Link  | Open `https://<YOUR_UNIVERSAL_LINK_DOMAIN>/...` on a device with the app  |
| Custom scheme   | Open `<YOUR_CUSTOM_SCHEME>://...` from Safari or another app               |

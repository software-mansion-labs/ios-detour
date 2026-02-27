# Example Usage (iOS)

## Replace These Placeholders

- `<YOUR_DETOUR_API_KEY>`
- `<YOUR_DETOUR_APP_ID>`
- `<YOUR_CUSTOM_SCHEME>` (example: `myapp`)
- `<YOUR_UNIVERSAL_LINK_DOMAIN>` (example: `example.godetour.link`)
- `<YOUR_SHORT_LINK_PATH>` (example: `s1`)
- `<YOUR_BUNDLE_IDENTIFIER>` (example: `com.company.app`)

## Files

- `DetourExampleApp/AppDelegate.swift`: app startup + deep-link handlers
- `DetourExampleApp/ContentView.swift`: manual link + analytics actions
- `DetourExampleApp/DetourDemoState.swift`: state/logging helper
- `DetourExampleApp/Info.plist`: custom URL scheme template
- `DetourExampleApp/DetourExample.entitlements`: Associated Domains template

## Integration Steps

1. Add `DetourIOS` package to your app target.
2. Copy `AppDelegate.swift`, `ContentView.swift`, and `DetourDemoState.swift` into your app.
3. Replace all placeholders.
4. Configure URL scheme in `Info.plist`.
5. Configure Associated Domains entitlement with your Detour domain.
6. Test:
   - custom scheme (`<YOUR_CUSTOM_SCHEME>://...`)
   - universal link (`https://<YOUR_UNIVERSAL_LINK_DOMAIN>/...`)
   - deferred link (fresh install / first launch)

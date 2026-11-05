import Detour

extension DetourConfig {
    static let example = DetourConfig(
        apiKey: "<YOUR_DETOUR_API_KEY>",
        appID: "<YOUR_DETOUR_APP_ID>",
        shouldUseClipboard: false,
        linkProcessingMode: .all
    )
}

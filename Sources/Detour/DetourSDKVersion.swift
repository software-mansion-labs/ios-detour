import Foundation

enum DetourSDKVersion {
    static let current = load()

    private static func load() -> String {
        for bundle in candidateBundles() {
            if let version = loadVersion(from: bundle) {
                return version
            }
        }

        return "unknown"
    }

    private static func loadVersion(from bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "detour_sdk_version", withExtension: "txt"),
              let version = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else {
            return nil
        }

        return version
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []

#if SWIFT_PACKAGE
        bundles.append(Bundle.module)
#endif

        bundles.append(Bundle(for: Detour.self))
        bundles.append(Bundle.main)

        return bundles
    }
}

import Foundation

// Mirrors `lib/services/eventsService/eventNames.ts` in detour-website. Keep in sync.
enum EventNameRules {
    static let pattern = "^[a-z0-9_]{1,64}$"

    /// `af_` marks events imported from AppsFlyer; `dt_` is kept for Detour's own names.
    static let reservedPrefixes = ["af_", "dt_"]

    /// The server turns these into link clicks, so an app may not log them itself.
    static let reservedNames: Set<String> = ["opened_via_universal_link"]

    /// The server's limit for `data`, as UTF-8 bytes of its JSON.
    static let maxDataBytes = 2048

    private static let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_")

    /// Why the server would refuse `name`, or `nil` when it is a valid event name.
    static func problem(_ name: String) -> String? {
        guard (1...64).contains(name.count), name.allSatisfy(allowedCharacters.contains) else {
            return "event names must match \(pattern)"
        }
        if reservedPrefixes.contains(where: name.hasPrefix) {
            return "the \(reservedPrefixes.joined(separator: " and ")) prefixes are reserved"
        }
        if reservedNames.contains(name) {
            return "this name is reserved for Detour"
        }
        return nil
    }
}

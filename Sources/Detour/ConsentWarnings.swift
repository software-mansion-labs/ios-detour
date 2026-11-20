import Foundation

/// Warnings about a consent integration that holds data back without saying so. Development
/// builds only, each once per launch.
@MainActor
enum ConsentWarnings {
    #if DEBUG
    static var isDevelopment = true
    #else
    static var isDevelopment = false
    #endif
    static var write: (String) -> Void = { DetourLogger.warn("Detour", $0) }
    private static var given: Set<String> = []

    static func warnOnce(_ key: String, _ message: String) {
        guard isDevelopment, given.insert(key).inserted else { return }
        write("[Detour:CONSENT] \(message)")
    }

    static func resetForTests() {
        given = []
    }
}

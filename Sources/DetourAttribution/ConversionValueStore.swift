import Detour
import Foundation

/// The cached schema and what this install already reported to SKAdNetwork.
@MainActor
final class ConversionValueStore {
    private struct CachedSchema: Codable {
        let etag: String?
        let body: Data
    }

    // Kept with the install ID: UserDefaults come back from a backup on a new install, which
    // must register again and starts its conversion value from zero.
    private struct InstallState: Codable {
        var installID: String
        var isRegistered = false
        var highestFine = -1
        var counts: [String: Int] = [:]
    }

    private static let schemaKey = "Detour_conversionValueSchema"
    private static let stateKey = "Detour_conversionValueState"

    private let defaults: UserDefaults
    private(set) var schema: ConversionValueSchema
    private var etag: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let cached = defaults.data(forKey: Self.schemaKey).flatMap { try? JSONDecoder().decode(CachedSchema.self, from: $0) }
        etag = cached?.etag
        schema = cached.flatMap { try? JSONDecoder().decode(ConversionValueSchema.self, from: $0.body) } ?? .empty
    }

    var schemaETag: String? { etag }

    /// A `304` or a failed fetch keeps the last schema.
    func apply(_ result: DetourFetchResult) {
        guard case let .updated(body, newETag) = result,
              let decoded = try? JSONDecoder().decode(ConversionValueSchema.self, from: body)
        else { return }
        schema = decoded
        etag = newETag
        if let data = try? JSONEncoder().encode(CachedSchema(etag: newETag, body: body)) {
            defaults.set(data, forKey: Self.schemaKey)
        }
    }

    func isRegistered(installID: String) -> Bool {
        state(installID).isRegistered
    }

    func markRegistered(installID: String) {
        update(installID) { $0.isRegistered = true }
    }

    /// Counts the conversion and returns how many with this name there were, this one included.
    func count(_ name: String, installID: String) -> Int {
        var count = 0
        update(installID) {
            count = ($0.counts[name] ?? 0) + 1
            $0.counts[name] = count
        }
        return count
    }

    /// The highest value SKAdNetwork took from this install, or -1 before the first one.
    func highestFine(installID: String) -> Int {
        state(installID).highestFine
    }

    /// Keeps the higher of the stored value and `fine`: SKAdNetwork takes only increases.
    func raiseHighestFine(to fine: Int, installID: String) {
        update(installID) { $0.highestFine = max($0.highestFine, fine) }
    }

    private func state(_ installID: String) -> InstallState {
        if let data = defaults.data(forKey: Self.stateKey),
           let stored = try? JSONDecoder().decode(InstallState.self, from: data),
           stored.installID == installID
        {
            return stored
        }
        return InstallState(installID: installID)
    }

    private func update(_ installID: String, _ change: (inout InstallState) -> Void) {
        var current = state(installID)
        change(&current)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }
}

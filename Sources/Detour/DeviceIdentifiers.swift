import CryptoKit
import Foundation

/// `advertising_id` in Detour requests.
struct AdvertisingID: Codable, Equatable {
    let id: String
    let type: String

    static func idfa(_ id: String) -> AdvertisingID {
        AdvertisingID(id: id, type: "idfa")
    }
}

/// The identifiers the SDK may send now, after the consent gate and the provider's own checks.
struct DeviceIdentifiers: Equatable {
    var advertisingID: AdvertisingID?

    static let none = DeviceIdentifiers()

    /// Each identifier the SDK has, as its JSON value, by request field name.
    var encodedFields: [String: Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var fields: [String: Data] = [:]
        fields["advertising_id"] = advertisingID.flatMap { try? encoder.encode($0) }
        return fields
    }
}

/// Sends identifiers that appear, change or go away after the first deferred match to
/// `sdk/device-identifiers`. One request at a time; a field goes out only when it differs from
/// what the server last answered for, so most launches send nothing.
@MainActor
final class DeviceIdentifiersReporter {
    typealias Send = (_ body: [String: Any]) async -> Bool

    // Holds hashes, not the identifiers, and the device ID they were sent for: UserDefaults come
    // back from a backup but the device ID does not, so a restored install sends them again.
    private struct Sent: Codable {
        let deviceID: String
        var hashes: [String: String]
    }

    private static let key = "Detour_sentDeviceIdentifiers"

    private let defaults: UserDefaults
    private let canSend: () -> Bool
    private let current: () -> DeviceIdentifiers
    private let deviceID: () -> String
    private let send: Send
    private var isSending = false
    private var needsAnotherSync = false

    init(
        defaults: UserDefaults = .standard,
        canSend: @escaping () -> Bool,
        current: @escaping () -> DeviceIdentifiers,
        deviceID: @escaping () -> String,
        send: @escaping Send
    ) {
        self.defaults = defaults
        self.canSend = canSend
        self.current = current
        self.deviceID = deviceID
        self.send = send
    }

    func sync() {
        guard !isSending else {
            needsAnotherSync = true
            return
        }
        guard canSend() else { return }
        let deviceID = deviceID()
        let sentHashes = loadSent(deviceID: deviceID)
        let (fields, hashes) = Self.changes(current: current().encodedFields, sentHashes: sentHashes)
        guard !fields.isEmpty else { return }

        isSending = true
        var body = fields
        body["device_id"] = deviceID
        Task {
            // Stored also after a rejection, so a value the server will not take is not sent on every launch.
            if await send(body) {
                save(Sent(deviceID: deviceID, hashes: hashes))
            }
            isSending = false
            if needsAnotherSync {
                needsAnotherSync = false
                sync()
            }
        }
    }

    /// The fields to send (a value, or `NSNull` to clear one sent before) and the hashes to store
    /// once the server answered.
    static func changes(current: [String: Data], sentHashes: [String: String]) -> (fields: [String: Any], hashes: [String: String]) {
        var fields: [String: Any] = [:]
        var hashes: [String: String] = [:]
        for (name, data) in current {
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            hashes[name] = hash
            if sentHashes[name] != hash {
                fields[name] = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            }
        }
        for name in sentHashes.keys where current[name] == nil {
            fields[name] = NSNull()
        }
        return (fields, hashes)
    }

    private func loadSent(deviceID: String) -> [String: String] {
        guard let data = defaults.data(forKey: Self.key),
              let sent = try? JSONDecoder().decode(Sent.self, from: data),
              sent.deviceID == deviceID
        else { return [:] }
        return sent.hashes
    }

    private func save(_ sent: Sent) {
        if let data = try? JSONEncoder().encode(sent) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

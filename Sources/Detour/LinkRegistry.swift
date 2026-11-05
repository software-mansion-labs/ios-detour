import Foundation

enum MonotonicClock {
    // Unlike Date, it does not jump when the user changes the device time.
    // Unlike systemUptime, it keeps counting while the device sleeps.
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

struct LinkRegistry<Value> {
    private struct Entry {
        let value: Value
        let storedAt: TimeInterval
    }

    private let window: TimeInterval
    private let now: () -> TimeInterval
    private var entries: [String: Entry] = [:]

    init(window: TimeInterval, now: @escaping () -> TimeInterval) {
        self.window = window
        self.now = now
    }

    func get(_ url: String) -> Value? {
        guard let entry = entries[Self.key(for: url)], now() - entry.storedAt < window else { return nil }
        return entry.value
    }

    mutating func set(_ url: String, _ value: Value) {
        let currentTime = now()
        entries = entries.filter { currentTime - $0.value.storedAt < window }
        entries[Self.key(for: url)] = Entry(value: value, storedAt: currentTime)
    }

    // Two spellings of one link, such as `//Example.com/x` and `https://example.com/x`, share one key.
    private static func key(for url: String) -> String {
        let normalized = LinkUtils.normalizeRawLink(url)
        guard let parsed = LinkUtils.parseUrl(normalized),
              var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
        else {
            return normalized
        }
        components.scheme = components.scheme?.lowercased()
        components.percentEncodedHost = components.percentEncodedHost?.lowercased()
        return components.string ?? normalized
    }
}

extension LinkRegistry where Value: Equatable {
    // Keeps a newer value stored for the same link in the meantime.
    mutating func forget(_ url: String, ifStored value: Value) {
        let key = Self.key(for: url)
        if entries[key]?.value == value {
            entries[key] = nil
        }
    }
}

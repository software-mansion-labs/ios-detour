import Foundation

/// Per-install state that must disappear with the app: the device ID and the first-launch flag.
/// Kept in a file excluded from backups, so a reinstall or a phone restored from a backup
/// starts with a new device ID and runs deferred matching again.
@MainActor
final class InstallStore {
    static let shared = InstallStore()

    private struct State: Codable {
        var deviceID: String
        var firstLaunchHandled: Bool
    }

    private enum LegacyKeys {
        static let deviceID = "Detour_deviceId"
        static let firstLaunchHandled = "DetourFirstEntranceFlag"
    }

    private let tag = "InstallStore"
    private let fileURL: URL
    private let defaults: UserDefaults
    private var state: State?

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let baseDirectory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseDirectory.appendingPathComponent("Detour", isDirectory: true)
            .appendingPathComponent("install.json")
        self.defaults = defaults
    }

    var deviceID: String { load().deviceID }

    var isFirstLaunch: Bool { !load().firstLaunchHandled }

    func markFirstLaunchHandled() {
        update { $0.firstLaunchHandled = true }
    }

    func resetFirstLaunch() {
        update { $0.firstLaunchHandled = false }
    }

    private func update(_ change: (inout State) -> Void) {
        var current = load()
        change(&current)
        state = current
        save(current)
    }

    private func load() -> State {
        if let state { return state }

        if let saved = readFile() {
            state = saved
            return saved
        }

        // PROVISIONAL: an app updated from an SDK that kept these values in UserDefaults keeps
        // its device ID and first-launch flag, so the update is not counted as a new install
        // and the deferred link is not opened again. The old keys are removed after the move.
        let legacy = legacyState()
        let created = legacy ?? State(deviceID: UUID().uuidString.lowercased(), firstLaunchHandled: false)
        state = created
        if save(created), legacy != nil {
            removeLegacyState()
        }
        return created
    }

    private func readFile() -> State? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let saved = try? JSONDecoder().decode(State.self, from: data),
              UUID(uuidString: saved.deviceID) != nil
        else {
            DetourLogger.warn(tag, "[Detour:STORAGE] Install state file is unreadable; starting a new install.")
            return nil
        }
        return State(deviceID: saved.deviceID.lowercased(), firstLaunchHandled: saved.firstLaunchHandled)
    }

    private func legacyState() -> State? {
        let legacyID = defaults.string(forKey: LegacyKeys.deviceID).flatMap(UUID.init(uuidString:))
        let legacyHandled = defaults.bool(forKey: LegacyKeys.firstLaunchHandled)
        guard legacyID != nil || legacyHandled else { return nil }

        return State(
            deviceID: (legacyID ?? UUID()).uuidString.lowercased(),
            firstLaunchHandled: legacyHandled
        )
    }

    private func removeLegacyState() {
        defaults.removeObject(forKey: LegacyKeys.deviceID)
        defaults.removeObject(forKey: LegacyKeys.firstLaunchHandled)
    }

    @discardableResult
    private func save(_ state: State) -> Bool {
        var directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try directory.setResourceValues(resourceValues)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            return true
        } catch {
            DetourLogger.error(tag, "[Detour:STORAGE] Failed to save install state.", error: error)
            return false
        }
    }
}

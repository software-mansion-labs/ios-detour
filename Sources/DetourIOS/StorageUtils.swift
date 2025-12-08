import Foundation

class StorageUtils {
    private static let key = "DetourFirstEntranceFlag"

    static func isFirstEntrance() -> Bool {
        return !UserDefaults.standard.bool(forKey: key)
    }

    static func markFirstEntrance() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

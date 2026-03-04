import Foundation

class StorageUtils {
    
    enum Constants {
        static let firstEntranceKey = "DetourFirstEntranceFlag"
        static let deviceIDKey = "Detour_deviceId"
    }

    static func isFirstEntrance() -> Bool {
        return !UserDefaults.standard.bool(forKey: Constants.firstEntranceKey)
    }

    static func markFirstEntrance() {
        UserDefaults.standard.set(true, forKey: Constants.firstEntranceKey)
    }
}

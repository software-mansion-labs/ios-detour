import Foundation

class StorageUtils {
    
    private enum Constants {
        static let firstEntranceKey = "DetourFirstEntranceFlag"
    }

    static func isFirstEntrance() -> Bool {
        return !UserDefaults.standard.bool(forKey: Constants.firstEntranceKey)
    }

    static func markFirstEntrance() {
        UserDefaults.standard.set(true, forKey: Constants.firstEntranceKey)
    }
}

import Foundation

/// The app's user identifier from `Detour.shared.setUserId`. Unlike the device ID it may come back
/// from a backup: on a new install it lets the backend recognise a returning user.
enum UserIdStore {
    private static let key = "Detour_userId"

    static var current: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// Built-in check for `setUserId` values, applied before `DetourConfig.userIdValidator`.
enum UserIdPolicy {
    // PROVISIONAL: accepts every value until it is decided whether the SDK itself rejects
    // values that look like e-mail addresses or phone numbers.
    static func isAllowed(_ userId: String) -> Bool {
        true
    }
}

import XCTest
@testable import Detour

@MainActor
final class InstallStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "InstallStoreTests"

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDeviceIDSurvivesRelaunchButNotReinstall() {
        let first = InstallStore(directory: directory, defaults: defaults).deviceID
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(first, first.lowercased())

        XCTAssertEqual(InstallStore(directory: directory, defaults: defaults).deviceID, first)

        // A reinstall or a restored phone has neither the file nor the legacy keys.
        let reinstalled = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: reinstalled) }
        XCTAssertNotEqual(InstallStore(directory: reinstalled, defaults: defaults).deviceID, first)
    }

    func testStateDirectoryIsExcludedFromBackup() throws {
        _ = InstallStore(directory: directory, defaults: defaults).deviceID

        let stateDirectory = directory.appendingPathComponent("Detour", isDirectory: true)
        let values = try stateDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testFirstLaunchFlagLivesWithDeviceID() {
        let store = InstallStore(directory: directory, defaults: defaults)
        XCTAssertTrue(store.isFirstLaunch)

        store.markFirstLaunchHandled()
        XCTAssertFalse(InstallStore(directory: directory, defaults: defaults).isFirstLaunch)

        store.resetFirstLaunch()
        XCTAssertTrue(InstallStore(directory: directory, defaults: defaults).isFirstLaunch)
    }

    func testUpdateFromUserDefaultsKeepsDeviceIDAndFlag() {
        defaults.set("3F2B8C1E-9D4A-4C55-8F0E-2A6B7C8D9E01", forKey: "Detour_deviceId")
        defaults.set(true, forKey: "DetourFirstEntranceFlag")

        let store = InstallStore(directory: directory, defaults: defaults)

        XCTAssertEqual(store.deviceID, "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01")
        XCTAssertFalse(store.isFirstLaunch)
        XCTAssertNil(defaults.object(forKey: "Detour_deviceId"))
        XCTAssertNil(defaults.object(forKey: "DetourFirstEntranceFlag"))
        XCTAssertEqual(InstallStore(directory: directory, defaults: defaults).deviceID, store.deviceID)
    }
}

final class MatchRequestIdentityTests: XCTestCase {
    private func encodedKeys(userID: String?) throws -> [String: Any] {
        let request = SignalMatchRequest(
            platform: "ios", model: "iPhone15,2", manufacturer: "Apple", systemVersion: "18.6",
            screenWidth: 393, screenHeight: 852, scale: 3, locale: [LocaleTag(languageTag: "pl-PL")],
            timezone: "Europe/Warsaw", userAgent: "ua", timestamp: 0, pastedLink: nil,
            deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01", userID: userID
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    func testSendsDeviceIDAndUserIDInSnakeCase() throws {
        let json = try encodedKeys(userID: "u_12345")

        XCTAssertEqual(json["device_id"] as? String, "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01")
        XCTAssertEqual(json["user_id"] as? String, "u_12345")
        XCTAssertEqual(json["systemVersion"] as? String, "18.6")
    }

    func testOmitsUserIDWhenNotSet() throws {
        XCTAssertNil(try encodedKeys(userID: nil)["user_id"])
    }
}

@MainActor
final class SetUserIdTests: XCTestCase {
    override func tearDown() async throws {
        UserIdStore.current = nil
        Detour.shared.mountAnalytics(config: DetourConfig(apiKey: "key", appID: "app"))
        Detour.shared.unmountAnalytics()
    }

    func testStoresAndRemovesUserID() {
        Detour.shared.setUserId("u_12345")
        XCTAssertEqual(UserIdStore.current, "u_12345")

        Detour.shared.setUserId(nil)
        XCTAssertNil(UserIdStore.current)
    }

    func testRejectedValueIsNotStoredAndClearsThePreviousOne() {
        Detour.shared.mountAnalytics(config: DetourConfig(
            apiKey: "key", appID: "app", userIdValidator: { !$0.contains("@") }
        ))
        Detour.shared.setUserId("u_12345")

        Detour.shared.setUserId("someone@example.com")

        XCTAssertNil(UserIdStore.current)
    }
}

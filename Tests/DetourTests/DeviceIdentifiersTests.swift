import XCTest
@testable import Detour

@MainActor
final class DeviceIdentifiersTests: XCTestCase {
    private final class Provider: DetourAttributionProvider, @unchecked Sendable {
        func didStart(_ host: DetourAttributionHost) {}
        func didLogConversion(_ conversion: DetourConversion) {}
        func attributionToken() async -> String? { nil }
        func advertisingID() -> String? { "6d92078a-8246-4ba4-ae5b-76104861e7dc" }
    }

    private let idfa = AdvertisingID.idfa("6d92078a-8246-4ba4-ae5b-76104861e7dc")

    override func tearDown() async throws {
        AttributionMode.register(nil)
    }

    func testTheAdvertisingIDNeedsConsentToSharingWithAdNetworks() {
        AttributionMode.register(Provider())

        XCTAssertEqual(AttributionMode.deviceIdentifiers(for: .mmp, adNetworkSharing: .send).advertisingID, idfa)
        XCTAssertNil(AttributionMode.deviceIdentifiers(for: .mmp, adNetworkSharing: .wait).advertisingID)
        XCTAssertNil(AttributionMode.deviceIdentifiers(for: .mmp, adNetworkSharing: .drop).advertisingID)
    }

    func testCoreSendsNoIdentifiers() {
        AttributionMode.register(Provider())

        XCTAssertEqual(AttributionMode.deviceIdentifiers(for: .core, adNetworkSharing: .send), .none)
    }

    func testOnlyChangedFieldsGoOutAndAGoneValueIsCleared() throws {
        let first = DeviceIdentifiersReporter.changes(current: DeviceIdentifiers(advertisingID: idfa).encodedFields, sentHashes: [:])
        let sentField = try XCTUnwrap(first.fields["advertising_id"] as? [String: String])
        XCTAssertEqual(sentField, ["id": idfa.id, "type": "idfa"])

        let unchanged = DeviceIdentifiersReporter.changes(current: DeviceIdentifiers(advertisingID: idfa).encodedFields, sentHashes: first.hashes)
        XCTAssertTrue(unchanged.fields.isEmpty)

        let withdrawn = DeviceIdentifiersReporter.changes(current: DeviceIdentifiers.none.encodedFields, sentHashes: first.hashes)
        XCTAssertTrue(withdrawn.fields["advertising_id"] is NSNull)
        XCTAssertTrue(withdrawn.hashes.isEmpty)
    }

    func testAnAnsweredStateIsNotSentAgainButAFailedOneIs() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceIdentifiersTests"))
        defaults.removePersistentDomain(forName: "DeviceIdentifiersTests")
        var bodies: [[String: Any]] = []
        var answer = false
        let reporter = DeviceIdentifiersReporter(
            defaults: defaults,
            canSend: { true },
            current: { DeviceIdentifiers(advertisingID: self.idfa) },
            deviceID: { "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01" },
            send: { body in
                bodies.append(body)
                return answer
            }
        )

        reporter.sync()
        await Task.yield()
        reporter.sync()
        await Task.yield()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.first?["device_id"] as? String, "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01")

        answer = true
        reporter.sync()
        await Task.yield()
        reporter.sync()
        await Task.yield()
        XCTAssertEqual(bodies.count, 3)
    }

    func testWhatTheFirstMatchCarriedIsNotSentAgain() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceIdentifiersMatchTests"))
        defaults.removePersistentDomain(forName: "DeviceIdentifiersMatchTests")
        var current = DeviceIdentifiers(advertisingID: idfa)
        var bodies: [[String: Any]] = []
        let reporter = DeviceIdentifiersReporter(
            defaults: defaults,
            canSend: { true },
            current: { current },
            deviceID: { "device" },
            send: { body in
                bodies.append(body)
                return true
            }
        )

        reporter.markSent(current, deviceID: "device")
        reporter.sync()
        await Task.yield()
        XCTAssertTrue(bodies.isEmpty)

        current = .none
        reporter.sync()
        await Task.yield()
        XCTAssertTrue(bodies.first?["advertising_id"] is NSNull)
    }

    func testIdentifiersGoOnlyAfterTheFirstMatchAndAsMmp() {
        XCTAssertTrue(DeviceIdentifiersReporter.canSend(isStarted: true, isMatchInFlight: false, isFirstLaunch: false, sdkPackage: .mmp))
        XCTAssertFalse(DeviceIdentifiersReporter.canSend(isStarted: false, isMatchInFlight: false, isFirstLaunch: false, sdkPackage: .mmp))
        XCTAssertFalse(DeviceIdentifiersReporter.canSend(isStarted: true, isMatchInFlight: true, isFirstLaunch: false, sdkPackage: .mmp))
        XCTAssertFalse(DeviceIdentifiersReporter.canSend(isStarted: true, isMatchInFlight: false, isFirstLaunch: true, sdkPackage: .mmp))
        XCTAssertFalse(DeviceIdentifiersReporter.canSend(isStarted: true, isMatchInFlight: false, isFirstLaunch: false, sdkPackage: .core))
    }

    func testTheMatchRequestCarriesTheAdvertisingID() throws {
        var request = SignalMatchRequest(
            platform: "ios", model: "iPhone15,2", manufacturer: "Apple", systemVersion: "18.6",
            screenWidth: 393, screenHeight: 852, scale: 3, locale: [LocaleTag(languageTag: "pl-PL")],
            timezone: "Europe/Warsaw", userAgent: "ua", timestamp: 0, pastedLink: nil,
            deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01", userID: nil
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(json["advertising_id"])

        request.advertisingID = idfa
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["advertising_id"] as? [String: String], ["id": idfa.id, "type": "idfa"])
    }
}

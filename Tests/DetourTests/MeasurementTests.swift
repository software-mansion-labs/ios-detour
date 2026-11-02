import XCTest
@testable import Detour

final class RequestContextTests: XCTestCase {
    private static let matchRequest = SignalMatchRequest(
        platform: "ios", model: "iPhone15,2", manufacturer: "Apple", systemVersion: "18.6",
        screenWidth: 393, screenHeight: 852, scale: 3, locale: [LocaleTag(languageTag: "pl-PL")],
        timezone: "Europe/Warsaw", userAgent: "ua", timestamp: 0, pastedLink: nil,
        deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01", userID: nil
    )

    func testMatchLinkBodyIsFlatAndKeepsTheLocaleSignals() throws {
        let context = RequestContext(appVersion: "4.2.0", locale: "pl-PL", attStatus: "denied").forMatchLink()
        let body = try JSONEncoder().encode(WithContext(body: Self.matchRequest, context: context))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["app_version"] as? String, "4.2.0")
        XCTAssertEqual(json["att_status"] as? String, "denied")
        XCTAssertEqual(json["device_id"] as? String, "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01")
        XCTAssertEqual((json["locale"] as? [[String: String]])?.first?["languageTag"], "pl-PL")
        XCTAssertNil(json["context"])
    }
}

final class SessionManagerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_730_000_000)
    private var events: [SessionManager.Event] = []
    private lazy var manager = SessionManager(now: { [unowned self] in self.clock })

    override func setUp() {
        super.setUp()
        manager.start { [unowned self] in self.events.append($0) }
    }

    override func tearDown() {
        manager.stop()
        super.tearDown()
    }

    private var startedID: String {
        guard case let .start(id, _) = events.first else { return "" }
        return id
    }

    func testBackgroundReportsTheEndWithItsDuration() {
        clock += 600
        manager.appDidEnterBackground()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last, .end(sessionID: startedID, at: clock, duration: 600))
        XCTAssertEqual(manager.currentSessionID, startedID)
    }

    func testShortTripToTheBackgroundKeepsTheSession() {
        manager.appDidEnterBackground()
        clock += SessionManager.backgroundTimeout
        manager.appWillEnterForeground()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(manager.currentSessionID, startedID)
    }

    func testLongTripToTheBackgroundStartsANewSession() {
        manager.appDidEnterBackground()
        clock += SessionManager.backgroundTimeout + 1
        manager.appWillEnterForeground()

        XCTAssertEqual(events.count, 3)
        guard case let .start(newID, at) = events.last else { return XCTFail("expected a new start") }
        XCTAssertNotEqual(newID, startedID)
        XCTAssertEqual(at, clock)
        XCTAssertEqual(manager.currentSessionID, newID)
    }

    func testSessionBodyFollowsTheContract() throws {
        let body = AnalyticsNetwork.body(
            of: .session(.end(sessionID: "8c1d2e3f-4a5b-4c6d-8e7f-901a2b3c4d5e", at: clock, duration: 1.2345)),
            deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01",
            userID: "u_12345"
        )

        XCTAssertEqual(body["type"] as? String, "end")
        XCTAssertEqual(body["session_id"] as? String, "8c1d2e3f-4a5b-4c6d-8e7f-901a2b3c4d5e")
        XCTAssertEqual(body["duration_ms"] as? Int, 1235)
        XCTAssertEqual(body["timestamp"] as? String, "2024-10-27T03:33:20.000Z")
        XCTAssertEqual(body["user_id"] as? String, "u_12345")
    }
}

final class ConversionBodyTests: XCTestCase {
    private func json(_ conversion: DetourConversion) throws -> [String: Any] {
        let body = AnalyticsNetwork.body(
            of: .conversion(conversion, at: Date(timeIntervalSince1970: 1_730_000_000)),
            deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01",
            userID: nil
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSendsTheContractFieldsWithExactRevenue() throws {
        let body = try json(DetourConversion(
            name: "ad_impression",
            revenue: Decimal(string: "0.001234")!,
            currency: "USD",
            revenueType: .inAppAds,
            transactionId: "t_1"
        ))

        XCTAssertEqual(body["revenue_type"] as? String, "in_app_ads")
        XCTAssertEqual((body["revenue"] as? NSNumber)?.decimalValue, Decimal(string: "0.001234"))
        XCTAssertEqual(body["transaction_id"] as? String, "t_1")
        XCTAssertEqual(body["timestamp"] as? String, "2024-10-27T03:33:20.000Z")
        XCTAssertNil(body["product_id"])
        XCTAssertNil(body["quantity"])
    }
}

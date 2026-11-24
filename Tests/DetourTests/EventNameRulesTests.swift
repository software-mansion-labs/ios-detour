import XCTest
@testable import Detour

final class EventNameRulesTests: XCTestCase {
    func testAcceptsEveryStandardName() {
        for name in DetourEventName.allCases {
            XCTAssertNil(EventNameRules.problem(name.rawValue), name.rawValue)
        }
    }

    func testAcceptsCustomNames() {
        for name in ["level_complete", "a", String(repeating: "x", count: 64), "step_2", "app_open"] {
            XCTAssertNil(EventNameRules.problem(name), name)
        }
    }

    func testRefusesNamesThatBreakThePattern() {
        for name in ["", "Level", "level-complete", "level complete", String(repeating: "x", count: 65), "zażółć"] {
            XCTAssertEqual(EventNameRules.problem(name), "event names must match ^[a-z0-9_]{1,64}$", name)
        }
    }

    func testRefusesReservedPrefixes() {
        for name in ["af_install", "dt_click"] {
            XCTAssertEqual(EventNameRules.problem(name), "the af_ and dt_ prefixes are reserved", name)
        }
    }

    func testRefusesOpenedViaUniversalLink() {
        XCTAssertEqual(EventNameRules.problem("opened_via_universal_link"), "this name is reserved for Detour")
    }
}

@MainActor
final class LogEventTests: XCTestCase {
    private var received: [AnalyticsEventPayload] = []
    private var token: UUID?

    override func setUp() async throws {
        received = []
        token = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            self?.received.append(payload)
        }
    }

    override func tearDown() async throws {
        if let token {
            AnalyticsEmitter.shared.unsubscribe(token)
        }
    }

    func testEmitsCustomNameWithData() {
        DetourAnalytics.logEvent("level_complete", data: ["level": 3])

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.eventName, "level_complete")
        XCTAssertEqual(received.first?.data?["level"] as? Int, 3)
    }

    func testEmitsStandardName() {
        DetourAnalytics.logEvent(.purchase)

        XCTAssertEqual(received.map(\.eventName), ["purchase"])
    }

    func testDropsInvalidNames() {
        for name in ["Level-Complete", "af_install", "opened_via_universal_link"] {
            DetourAnalytics.logEvent(name)
        }

        XCTAssertTrue(received.isEmpty)
    }

    func testSendsLargeData() {
        DetourAnalytics.logEvent("big_event", data: ["text": String(repeating: "x", count: 3000)])

        XCTAssertEqual(received.count, 1)
    }
}

final class RefusalMessageTests: XCTestCase {
    private func message(_ statusCode: Int, _ body: String = "{}") -> String {
        AnalyticsNetwork.refusalMessage(statusCode: statusCode, body: Data(body.utf8), eventName: "level_complete")
    }

    func testUsesTheServerMessageForANameRefusal() {
        let body = #"{"error":{"formErrors":[],"fieldErrors":{"event_name":["the App already has 500 custom event names"]}}}"#

        XCTAssertEqual(
            message(400, body),
            #"Event "level_complete" refused: the App already has 500 custom event names."#
        )
    }

    func testFallsBackToTheStatusForA400WithoutANameError() {
        XCTAssertEqual(message(400, #"{"error":{"fieldErrors":{"data":["too big"]}}}"#), "event send failed: 400")
        XCTAssertEqual(message(400, "not json"), "event send failed: 400")
    }

    func testDescribesTooLargeAndRateLimited() {
        XCTAssertEqual(message(413), #"Event "level_complete" refused: the request body is too large."#)
        XCTAssertEqual(message(429), #"Event "level_complete" refused: rate limit exceeded."#)
    }

    func testFallsBackToTheStatusCode() {
        XCTAssertEqual(message(500), "event send failed: 500")
    }
}

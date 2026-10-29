import XCTest
@testable import Detour

final class UniversalLinkClicksTests: XCTestCase {
    private let clickPath = "/api/link/universal-link-click"
    private let config = DetourConfig(apiKey: "test-key", appID: "test-app")
    private let url = "https://example.com/promo/offer"
    private let clock = TestClock()

    override class func setUp() {
        super.setUp()
        StubURLProtocol.install()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    @MainActor
    private func makeClicks() -> UniversalLinkClicks {
        UniversalLinkClicks(now: { [clock] in clock.now })
    }

    @MainActor
    func testRepeatWithinWindowSendsNoRequest() async {
        let clicks = makeClicks()

        _ = await clicks.record(config: config, url: url)
        clock.advance(by: 9)
        let repeated = await clicks.record(config: config, url: url)

        XCTAssertTrue(repeated.allowed)
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testConcurrentCallsShareOneRequest() async {
        let clicks = makeClicks()

        async let first = clicks.record(config: config, url: url)
        async let second = clicks.record(config: config, url: url)
        let results = await [first.allowed, second.allowed]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testClickAfterWindowIsSentAgain() async {
        let clicks = makeClicks()

        _ = await clicks.record(config: config, url: url)
        clock.advance(by: UniversalLinkClicks.repeatWindow)
        _ = await clicks.record(config: config, url: url)

        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testServerErrorIsNotRememberedAndFailsOpen() async {
        StubURLProtocol.reply(to: clickPath, with: .status(500))
        let clicks = makeClicks()

        let failed = await clicks.record(config: config, url: url)
        let retried = await clicks.record(config: config, url: url)

        XCTAssertTrue(failed.allowed)
        XCTAssertTrue(retried.allowed)
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testNetworkErrorIsNotRememberedAndFailsOpen() async {
        StubURLProtocol.reply(to: clickPath, with: .failure(.notConnectedToInternet))
        let clicks = makeClicks()

        let failed = await clicks.record(config: config, url: url)
        StubURLProtocol.reply(to: clickPath, with: .status(200, body: #"{"allowed":true,"clickId":"click-1"}"#))
        let retried = await clicks.record(config: config, url: url)

        XCTAssertTrue(failed.allowed)
        XCTAssertEqual(retried.clickId, "click-1")
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testDeniedClickIsRemembered() async {
        StubURLProtocol.reply(to: clickPath, with: .status(402))
        let clicks = makeClicks()

        let denied = await clicks.record(config: config, url: url)
        let repeated = await clicks.record(config: config, url: url)

        XCTAssertFalse(denied.allowed)
        XCTAssertFalse(repeated.allowed)
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testOtherLinkSendsItsOwnClick() async {
        let clicks = makeClicks()

        _ = await clicks.record(config: config, url: url)
        _ = await clicks.record(config: config, url: "https://example.com/promo/other")

        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }
}

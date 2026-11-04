import XCTest
@testable import Detour

final class UniversalLinkClickRecorderTests: NetworkStubbedTestCase {
    private let clickPath = APIPath.universalLinkClick
    private let config = DetourConfig.test()
    private let url = "https://example.com/promo/offer"
    private let clock = TestClock()

    @MainActor
    private func makeRecorder() -> UniversalLinkClickRecorder {
        UniversalLinkClickRecorder(now: { [clock] in clock.now })
    }

    @MainActor
    func testRepeatWithinWindowSendsNoRequest() async {
        let recorder = makeRecorder()

        _ = await recorder.record(config: config, url: url)
        clock.advance(by: 9)
        let repeated = await recorder.record(config: config, url: url)

        XCTAssertEqual(repeated, .allowed(clickId: nil))
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testConcurrentCallsShareOneRequest() async {
        let recorder = makeRecorder()

        async let first = recorder.record(config: config, url: url)
        async let second = recorder.record(config: config, url: url)
        let outcomes = await [first, second]

        XCTAssertEqual(outcomes, [.allowed(clickId: nil), .allowed(clickId: nil)])
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testClickAfterWindowIsSentAgain() async {
        let recorder = makeRecorder()

        _ = await recorder.record(config: config, url: url)
        clock.advance(by: UniversalLinkClickRecorder.repeatWindow)
        _ = await recorder.record(config: config, url: url)

        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testServerErrorIsNotRemembered() async {
        StubURLProtocol.reply(to: clickPath, with: .status(500))
        let recorder = makeRecorder()

        let failed = await recorder.record(config: config, url: url)
        let retried = await recorder.record(config: config, url: url)

        XCTAssertEqual(failed, .notSaved)
        XCTAssertEqual(retried, .notSaved)
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testNetworkErrorIsNotRemembered() async {
        StubURLProtocol.reply(to: clickPath, with: .failure(.notConnectedToInternet))
        let recorder = makeRecorder()

        let failed = await recorder.record(config: config, url: url)
        StubURLProtocol.reply(to: clickPath, with: .status(200, body: #"{"allowed":true,"clickId":"click-1"}"#))
        let retried = await recorder.record(config: config, url: url)

        XCTAssertEqual(failed, .notSaved)
        XCTAssertEqual(retried, .allowed(clickId: "click-1"))
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }

    @MainActor
    func testDeniedClickIsRemembered() async {
        StubURLProtocol.reply(to: clickPath, with: .status(402))
        let recorder = makeRecorder()

        let denied = await recorder.record(config: config, url: url)
        let repeated = await recorder.record(config: config, url: url)

        XCTAssertEqual(denied, .denied)
        XCTAssertEqual(repeated, .denied)
        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 1)
    }

    @MainActor
    func testOtherLinkSendsItsOwnClick() async {
        let recorder = makeRecorder()

        _ = await recorder.record(config: config, url: url)
        _ = await recorder.record(config: config, url: "https://example.com/promo/other")

        XCTAssertEqual(StubURLProtocol.requestCount(to: clickPath), 2)
    }
}

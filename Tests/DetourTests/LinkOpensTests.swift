import XCTest
@testable import Detour

final class LinkOpensTests: XCTestCase {
    private let url = "https://example.com/promo/offer"
    private let clock = TestClock()

    private func makeOpens() -> LinkOpens {
        LinkOpens(now: { [clock] in clock.now })
    }

    func testSameTapDeliveredTwiceOpensOnce() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimCallbackLink(url))
        clock.advance(by: 0.5)
        XCTAssertFalse(opens.claimCallbackLink(url))
    }

    func testTappingLinkAgainOpensItAgain() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimCallbackLink(url))
        clock.advance(by: 1)
        XCTAssertTrue(opens.claimCallbackLink(url))
    }

    func testOtherLinkOpens() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimCallbackLink(url))
        XCTAssertTrue(opens.claimCallbackLink("https://example.com/promo/other"))
    }

    func testSpellingsOfOneLinkShareOneOpen() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimCallbackLink("//Example.com/promo/offer"))
        XCTAssertFalse(opens.claimCallbackLink("HTTPS://example.com/promo/offer"))
    }

    func testRedeliveredLaunchLinkIsSkippedOnce() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimLaunchLink(url, willBeRedelivered: true))
        clock.advance(by: 5)
        XCTAssertFalse(opens.claimCallbackLink(url))
        clock.advance(by: 1)
        XCTAssertTrue(opens.claimCallbackLink(url))
    }

    func testRedeliveryWaitEnds() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimLaunchLink(url, willBeRedelivered: true))
        clock.advance(by: LinkOpens.redeliveryWindow)
        XCTAssertTrue(opens.claimCallbackLink(url))
    }

    func testSceneLaunchLinkLetsNextTapThrough() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimLaunchLink(url, willBeRedelivered: false))
        clock.advance(by: 0.5)
        XCTAssertFalse(opens.claimCallbackLink(url))
        clock.advance(by: 1)
        XCTAssertTrue(opens.claimCallbackLink(url))
    }

    func testLaunchLinkDeliveredByCallbackFirstIsSkipped() {
        var opens = makeOpens()

        XCTAssertTrue(opens.claimCallbackLink(url))
        clock.advance(by: 3)
        XCTAssertFalse(opens.claimLaunchLink(url, willBeRedelivered: true))
    }
}

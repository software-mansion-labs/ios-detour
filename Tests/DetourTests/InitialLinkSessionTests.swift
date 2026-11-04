import XCTest
@testable import Detour

final class InitialLinkSessionTests: XCTestCase {
    private let link = URL(string: "https://example.com/promo/offer")!

    func testLaunchLinkOpensOnce() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .all), .open(link))
        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .all), .skip)
    }

    func testSceneLinkOpensOnceAfterAppDelegateFoundNone() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(), mode: .all), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(), mode: .all), .skip)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
        XCTAssertTrue(session.isDeferredLinkReplaced)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .skip)
    }

    func testSceneOnlySessionSkipsLaterSceneLinks() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .scene(), mode: .all), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .skip)
        XCTAssertFalse(session.isDeferredLinkReplaced)
    }

    func testActivityWithoutURLWaitsForContinueCallback() {
        var session = InitialLinkSession()
        let launch = LaunchContext(candidateURLs: [nil], hasBrowsingActivity: true, source: .launchOptions)

        XCTAssertEqual(session.action(for: launch, mode: .all), .awaitContinueCallback)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .skip)
    }

    func testDeferredOnlyIgnoresLaunchLink() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .deferredOnly), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .deferredOnly), .skip)
    }

    func testWebOnlySchemeLaunchLinkFallsBackToDeferredLink() {
        var session = InitialLinkSession()
        let schemeLink = URL(string: "myapp://product/42")!

        XCTAssertEqual(session.action(for: .appDelegate(url: schemeLink), mode: .webOnly), .resolveDeferred)
    }

    func testResetStartsNewSession() {
        var session = InitialLinkSession()

        _ = session.action(for: .appDelegate(url: link), mode: .all)
        session.reset()

        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .all), .open(link))
    }

    func testLaunchContextSkipsInfrastructureURL() {
        let launch = LaunchContext(candidateURLs: [URL(string: "about:blank"), link], hasBrowsingActivity: true, source: .launchOptions)

        XCTAssertEqual(launch.url, link)
        XCTAssertFalse(launch.waitsForContinueCallback)
    }
}

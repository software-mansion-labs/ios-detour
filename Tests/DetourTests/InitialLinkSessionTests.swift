import XCTest
@testable import Detour

final class InitialLinkSessionTests: XCTestCase {
    private let link = URL(string: "https://example.com/promo/offer")!

    func testAppDelegateLaunchLinkIsLeftToCallback() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .all), .awaitCallback)
        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .all), .skip)
    }

    func testSceneLaunchLinkOpens() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
    }

    func testSceneLinkOpensAfterAppDelegateFoundNone() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(), mode: .all), .resolveDeferred)
        XCTAssertEqual(session.action(for: .appDelegate(), mode: .all), .skip)
        XCTAssertEqual(session.action(for: .scene(), mode: .all), .skip)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
    }

    func testLaterSceneOpensItsLinkWithoutDeferredMatching() {
        var session = InitialLinkSession()
        let schemeLink = URL(string: "myapp://product/42")!

        XCTAssertEqual(session.action(for: .scene(), mode: .all), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
        XCTAssertEqual(session.action(for: .scene(), mode: .all), .skip)
        XCTAssertEqual(session.action(for: .scene(url: schemeLink), mode: .all), .open(schemeLink))
    }

    func testSceneAfterSceneLaunchLinkOpensItsLink() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
    }

    func testLaterSceneSkipsLinkTheModeIgnores() {
        var session = InitialLinkSession()
        let schemeLink = URL(string: "myapp://product/42")!

        XCTAssertEqual(session.action(for: .scene(), mode: .webOnly), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(url: schemeLink), mode: .webOnly), .skip)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .deferredOnly), .skip)
    }

    func testActivityWithoutURLWaitsForContinueCallback() {
        var session = InitialLinkSession()
        let launch = LaunchContext(candidateURLs: [nil], hasBrowsingActivity: true, source: .launchOptions)

        XCTAssertEqual(session.action(for: launch, mode: .all), .awaitCallback)
        XCTAssertEqual(session.action(for: launch, mode: .all), .skip)
    }

    func testDeferredOnlyIgnoresLaunchLink() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(url: link), mode: .deferredOnly), .resolveDeferred)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .deferredOnly), .skip)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .deferredOnly), .skip)
    }

    func testWebOnlySchemeLaunchLinkFallsBackToDeferredLink() {
        var session = InitialLinkSession()
        let schemeLink = URL(string: "myapp://product/42")!

        XCTAssertEqual(session.action(for: .appDelegate(url: schemeLink), mode: .webOnly), .resolveDeferred)
    }

    func testLinkOpenedDuringDeferredMatchReplacesDeferredLink() {
        var session = InitialLinkSession()

        let match = session.startDeferredMatch()
        session.linkOpened()

        XCTAssertEqual(session.finishDeferredMatch(match), .replaced)
    }

    func testLaterSceneLinkReplacesRunningDeferredMatchAtOnce() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(), mode: .all), .resolveDeferred)
        let match = session.startDeferredMatch()
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))

        XCTAssertEqual(session.finishDeferredMatch(match), .replaced)
    }

    func testLaterSceneWithoutLinkKeepsRunningDeferredMatch() {
        var session = InitialLinkSession()

        XCTAssertEqual(session.action(for: .appDelegate(), mode: .all), .resolveDeferred)
        let match = session.startDeferredMatch()
        XCTAssertEqual(session.action(for: .scene(), mode: .all), .skip)
        XCTAssertEqual(session.action(for: .scene(url: link), mode: .deferredOnly), .skip)

        XCTAssertEqual(session.finishDeferredMatch(match), .kept)
    }

    func testLinkOpenedOutsideDeferredMatchKeepsDeferredLink() {
        var session = InitialLinkSession()

        session.linkOpened()
        let match = session.startDeferredMatch()

        XCTAssertEqual(session.finishDeferredMatch(match), .kept)
    }

    func testFinishedMatchDoesNotEndOverlappingMatch() {
        var session = InitialLinkSession()

        let first = session.startDeferredMatch()
        let second = session.startDeferredMatch()
        XCTAssertEqual(session.finishDeferredMatch(first), .kept)
        session.linkOpened()

        XCTAssertEqual(session.finishDeferredMatch(second), .replaced)
    }

    func testLinkOpenedAfterResetReplacesRunningMatch() {
        var session = InitialLinkSession()

        let match = session.startDeferredMatch()
        session.reset()
        session.linkOpened()

        XCTAssertEqual(session.finishDeferredMatch(match), .replaced)
    }

    func testResetStartsNewSession() {
        var session = InitialLinkSession()

        _ = session.action(for: .scene(url: link), mode: .all)
        session.reset()

        XCTAssertEqual(session.action(for: .scene(url: link), mode: .all), .open(link))
    }

    func testLaunchContextSkipsInfrastructureURL() {
        let launch = LaunchContext(candidateURLs: [URL(string: "about:blank"), link], hasBrowsingActivity: true, source: .launchOptions)

        XCTAssertEqual(launch.url, link)
        XCTAssertFalse(launch.waitsForContinueCallback)
    }
}

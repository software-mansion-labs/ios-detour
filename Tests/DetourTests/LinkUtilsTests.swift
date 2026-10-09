import XCTest
@testable import Detour

final class LinkUtilsTests: XCTestCase {
    func testLooksLikeUrlNeedsSchemeBeforeFirstColon() {
        XCTAssertTrue(LinkUtils.looksLikeUrl("https://example.com/hash/p"))
        XCTAssertTrue(LinkUtils.looksLikeUrl("myapp://product/1"))
        XCTAssertTrue(LinkUtils.looksLikeUrl("myapp:product/1?x=1"))
        XCTAssertTrue(LinkUtils.looksLikeUrl("//example.com/hash/p"))

        XCTAssertFalse(LinkUtils.looksLikeUrl("/hash/p?redirect=https://x.com/y"))
        XCTAssertFalse(LinkUtils.looksLikeUrl("/hash/product:1?x=1"))
        XCTAssertFalse(LinkUtils.looksLikeUrl("hash/time/12:30?x=1"))
    }

    func testPathLinkDropsFragment() {
        let link = LinkUtils.makeDetourLink(fromPath: "/hash/p?x=1#top", type: .deferred)
        XCTAssertEqual(link.route, "/p?x=1")
        XCTAssertEqual(link.pathname, "/p")
        XCTAssertEqual(link.params, ["x": "1"])
    }

    func testPathLinkKeepsColonInQuery() {
        let link = LinkUtils.makeDetourLink(fromPath: "/hash/p?redirect=https://x.com/y", type: .deferred)
        XCTAssertEqual(link.route, "/p?redirect=https://x.com/y")
        XCTAssertEqual(link.params, ["redirect": "https://x.com/y"])
    }

    func testDeepLinkRouteStaysPercentEncoded() {
        let url = URL(string: "myapp://a%3Fb/product/hello%20world?q=a%26b#top")!
        XCTAssertEqual(LinkUtils.routeFromDeepLink(url), "/a%3Fb/product/hello%20world?q=a%26b")
        XCTAssertEqual(LinkUtils.routeFromDeepLink(URL(string: "myapp:product/1?x=1")!), "/product/1?x=1")
        XCTAssertEqual(LinkUtils.routeFromDeepLink(URL(string: "myapp://user@product:8080/x")!), "/product:8080/x")
    }

    func testWebLinkRouteStaysPercentEncoded() {
        let link = LinkUtils.makeDetourLink(from: URL(string: "https://example.com/hash/a%20b?q=1#top")!, type: .verified)
        XCTAssertEqual(link.route, "/a%20b?q=1")
        XCTAssertEqual(link.pathname, "/a%20b")
    }

    func testParseParamsDecodesLikeUrlSearchParams() {
        XCTAssertEqual(
            LinkUtils.parseParams(from: "a=hello+world&b=hello+50%off&c=100%25%off&=5"),
            ["a": "hello world", "b": "hello 50%off", "c": "100%%off", "": "5"]
        )
    }

    func testRawQueryIgnoresFragment() {
        XCTAssertEqual(LinkUtils.rawQuery(of: "https://x.com/abc/promo?id=5#section"), "id=5")
        XCTAssertNil(LinkUtils.rawQuery(of: "https://x.com/abc/promo#section?id=5"))
        XCTAssertEqual(LinkUtils.rawQuery(of: "https://x.com/abc/promo?utm=50%off"), "utm=50%off")
    }
}

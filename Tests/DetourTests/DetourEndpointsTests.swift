import XCTest
@testable import Detour

final class DetourEndpointsTests: XCTestCase {
    private func config(baseURL: String?) -> DetourConfig {
        DetourConfig(apiKey: "key", appID: "app", baseURL: baseURL.flatMap(URL.init(string:)))
    }

    func testDefaultBaseURLKeepsProductionAddresses() {
        let expected: [DetourEndpoint: String] = [
            .matchLink: "https://godetour.dev/api/link/match-link",
            .resolveShort: "https://godetour.dev/api/link/resolve-short",
            .universalLinkClick: "https://godetour.dev/api/link/universal-link-click",
            .analyticsEvent: "https://godetour.dev/api/analytics/event",
            .analyticsRetention: "https://godetour.dev/api/analytics/retention",
        ]
        XCTAssertEqual(Set(expected.keys), Set(DetourEndpoint.allCases))

        for (endpoint, url) in expected {
            XCTAssertEqual(DetourEndpoints.url(endpoint, config: config(baseURL: nil))?.absoluteString, url)
        }
    }

    func testCustomBaseURLIsUsedForEveryEndpoint() {
        let custom = config(baseURL: "https://api.example.com")
        for endpoint in DetourEndpoint.allCases {
            XCTAssertEqual(
                DetourEndpoints.url(endpoint, config: custom)?.absoluteString,
                "https://api.example.com/\(endpoint.rawValue)"
            )
        }
    }

    func testCustomBaseURLKeepsPathAndIgnoresTrailingSlash() {
        XCTAssertEqual(
            DetourEndpoints.url(.analyticsEvent, config: config(baseURL: "https://example.com/detour/"))?.absoluteString,
            "https://example.com/detour/api/analytics/event"
        )
    }

    func testNonHttpsBaseURLIsRejected() {
        XCTAssertNil(DetourEndpoints.url(.matchLink, config: config(baseURL: "http://localhost:3000")))
        XCTAssertNil(DetourEndpoints.url(.matchLink, config: config(baseURL: "ftp://example.com")))
        XCTAssertNil(DetourEndpoints.url(.matchLink, config: config(baseURL: "https:")))
    }
}

final class DetourNetworkBaseURLTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
        URLProtocol.registerClass(RecordingURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RecordingURLProtocol.self)
        super.tearDown()
    }

    func testAllRequestsGoToConfiguredHost() async {
        let config = DetourConfig(apiKey: "key", appID: "app", baseURL: URL(string: "https://api.example.com"))

        _ = await DetourNetwork.resolveShortLink(config: config, url: "https://app.godetour.link/abc")
        _ = await DetourNetwork.sendUniversalLinkClick(config: config, url: "https://app.godetour.link/abc")
        await AnalyticsNetwork.sendEvent(config: config, eventName: "test", data: nil, deviceID: "device")
        await AnalyticsNetwork.sendRetentionEvent(config: config, eventName: "app_open", deviceID: "device")

        let matched = expectation(description: "match-link completed")
        DetourNetwork.matchLink(config: config, fingerprint: Self.fingerprint) { _ in matched.fulfill() }
        await fulfillment(of: [matched], timeout: 5)

        XCTAssertEqual(
            Set(RecordingURLProtocol.recordedURLs.map(\.absoluteString)),
            Set(DetourEndpoint.allCases.map { "https://api.example.com/\($0.rawValue)" })
        )
    }

    func testInvalidBaseURLSendsNoRequests() async {
        let config = DetourConfig(apiKey: "key", appID: "app", baseURL: URL(string: "http://api.example.com"))

        _ = await DetourNetwork.resolveShortLink(config: config, url: "https://app.godetour.link/abc")
        await AnalyticsNetwork.sendEvent(config: config, eventName: "test", data: nil, deviceID: "device")

        let matched = expectation(description: "match-link completed")
        DetourNetwork.matchLink(config: config, fingerprint: Self.fingerprint) { _ in matched.fulfill() }
        await fulfillment(of: [matched], timeout: 5)

        XCTAssertTrue(RecordingURLProtocol.recordedURLs.isEmpty)
    }

    private static let fingerprint = ProbabilisticFingerprint(
        platform: "ios",
        model: "iPhone",
        manufacturer: "Apple",
        systemVersion: "18.0",
        screenWidth: 390,
        screenHeight: 844,
        scale: 3,
        locale: [LocaleTag(languageTag: "pl-PL")],
        timezone: "Europe/Warsaw",
        userAgent: "test",
        timestamp: 0,
        pastedLink: nil
    )
}

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var urls: [URL] = []

    static var recordedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    static func reset() {
        lock.lock()
        urls = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.lock.lock()
            Self.urls.append(url)
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

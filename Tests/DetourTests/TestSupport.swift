import Foundation

// Answers every request made through URLSession.shared, so tests never reach the Detour API.
final class StubURLProtocol: URLProtocol {
    enum Reply {
        case status(Int, body: String = "{}")
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    private static var replies: [String: Reply] = [:]
    private static var requestedPaths: [String] = []

    // Stays installed for the whole run: analytics requests can start after a test ends.
    private static let installation: Void = {
        URLProtocol.registerClass(StubURLProtocol.self)
    }()

    static func install() {
        _ = installation
    }

    static func reply(to path: String, with reply: Reply) {
        lock.lock()
        defer { lock.unlock() }
        replies[path] = reply
    }

    static func requestCount(to path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestedPaths.filter { $0 == path }.count
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        replies = [:]
        requestedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        Self.lock.lock()
        Self.requestedPaths.append(url.path)
        let reply = Self.replies[url.path] ?? .status(200)
        Self.lock.unlock()

        switch reply {
        case let .status(statusCode, body):
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

final class TestClock: @unchecked Sendable {
    private(set) var now: TimeInterval = 1_000

    func advance(by seconds: TimeInterval) {
        now += seconds
    }
}

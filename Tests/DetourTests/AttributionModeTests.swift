import XCTest
@testable import Detour

@MainActor
final class AttributionModeTests: XCTestCase {
    private final class RecordingProvider: DetourAttributionProvider, @unchecked Sendable {
        var conversions: [String] = []
        var starts = 0

        func didStart(_ host: DetourAttributionHost) {
            starts += 1
        }

        func didLogConversion(_ conversion: DetourConversion) {
            conversions.append(conversion.name)
        }

        func attributionToken() async -> String? {
            nil
        }
    }

    private let provider = RecordingProvider()
    private let purchase = DetourConversion(name: "purchase", revenue: 10, currency: "USD", revenueType: .iap)

    override func setUp() async throws {
        AttributionMode.register(provider)
    }

    override func tearDown() async throws {
        AttributionMode.register(nil)
    }

    func testRequestsGoAsCoreWithoutTheAttributionProduct() {
        XCTAssertEqual(AttributionMode.sdkPackage(hasProvider: false, decision: .send), .core)
    }

    func testRequestsGoAsMmpOnlyWhenTheAttributionGateLetsThemThrough() {
        XCTAssertEqual(AttributionMode.sdkPackage(hasProvider: true, decision: .send), .mmp)
        XCTAssertEqual(AttributionMode.sdkPackage(hasProvider: true, decision: .wait), .core)
        XCTAssertEqual(AttributionMode.sdkPackage(hasProvider: true, decision: .drop), .core)
    }

    func testTheProviderStartsOnceWhenTheSdkStartsAgain() {
        let config = DetourConfig(apiKey: "key", appID: "app")

        AttributionMode.start(config: config)
        AttributionMode.start(config: config)

        XCTAssertEqual(provider.starts, 1)
    }

    func testConversionsReachTheProviderOnlyWithAttributionConsent() {
        AttributionMode.forwardConversion(purchase, decision: .wait)
        AttributionMode.forwardConversion(purchase, decision: .drop)
        XCTAssertEqual(provider.conversions, [])

        AttributionMode.forwardConversion(purchase, decision: .send)
        XCTAssertEqual(provider.conversions, ["purchase"])
    }
}

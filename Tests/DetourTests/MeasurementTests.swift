import XCTest
@testable import Detour

final class RequestContextTests: XCTestCase {
    private static let matchRequest = SignalMatchRequest(
        platform: "ios", model: "iPhone15,2", manufacturer: "Apple", systemVersion: "18.6",
        screenWidth: 393, screenHeight: 852, scale: 3, locale: [LocaleTag(languageTag: "pl-PL")],
        timezone: "Europe/Warsaw", userAgent: "ua", timestamp: 0, pastedLink: nil,
        deviceID: "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01", userID: nil
    )

    func testMatchLinkBodyIsFlatAndKeepsTheLocaleSignals() throws {
        let context = RequestContext(appVersion: "4.2.0", locale: "pl-PL", attStatus: "denied").forMatchLink()
        let body = try JSONEncoder().encode(WithContext(body: Self.matchRequest, context: context))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["app_version"] as? String, "4.2.0")
        XCTAssertEqual(json["att_status"] as? String, "denied")
        XCTAssertEqual(json["device_id"] as? String, "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01")
        XCTAssertEqual((json["locale"] as? [[String: String]])?.first?["languageTag"], "pl-PL")
        XCTAssertNil(json["context"])
    }
}

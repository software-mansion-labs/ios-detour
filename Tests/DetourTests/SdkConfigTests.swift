import XCTest
@testable import Detour

@MainActor
final class SdkConfigTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SdkConfigTests"

    private static let body = Data("""
    {
      "schema_version": 1,
      "purposes": ["analytics", "attribution", "ad_network_sharing", "ad_personalization"],
      "consent_gate_default": {
        "analytics": "closed",
        "attribution": "closed",
        "ad_network_sharing": "closed",
        "ad_personalization": "closed"
      },
      "attribution_window_days_default": 7,
      "retention": { "gclid_days": 180, "raw_events_days": null },
      "features": { "postbacks_enabled": false, "attribution_enabled": false },
      "feature_flags": { "store_gclid_on_device": false, "read_app_set_id": false }
    }
    """.utf8)

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFallbackOpensOnlyAnalytics() {
        let store = SdkConfigStore(defaults: defaults)
        XCTAssertEqual(store.current.gateDefault(for: "analytics"), .open)
        XCTAssertEqual(store.current.gateDefault(for: "attribution"), .closed)
    }

    func testServerValuesReplaceTheFallbackAndSurviveRelaunch() {
        let store = SdkConfigStore(defaults: defaults)
        XCTAssertTrue(store.apply(.updated(body: Self.body, etag: "\"v1\""), appID: "app"))
        XCTAssertEqual(store.current.gateDefault(for: "analytics"), .closed)

        let relaunched = SdkConfigStore(defaults: defaults)
        relaunched.load(appID: "app")
        XCTAssertEqual(relaunched.current.gateDefault(for: "analytics"), .closed)
        XCTAssertEqual(relaunched.etag, "\"v1\"")
    }

    func testCacheOfAnotherAppIsIgnored() {
        SdkConfigStore(defaults: defaults).apply(.updated(body: Self.body, etag: nil), appID: "other")

        let store = SdkConfigStore(defaults: defaults)
        store.load(appID: "app")
        XCTAssertEqual(store.current, .fallback)
        XCTAssertNil(store.etag)
    }

    func testNotModifiedAndFailureKeepTheLastConfig() {
        let store = SdkConfigStore(defaults: defaults)
        store.apply(.updated(body: Self.body, etag: "\"v1\""), appID: "app")

        XCTAssertFalse(store.apply(.notModified, appID: "app"))
        XCTAssertFalse(store.apply(.failed, appID: "app"))
        XCTAssertEqual(store.current.gateDefault(for: "analytics"), .closed)
        XCTAssertEqual(store.etag, "\"v1\"")
    }

    func testBodyInAnUnexpectedShapeIsIgnored() {
        let store = SdkConfigStore(defaults: defaults)
        let unexpected = Data(#"{"schema_version": 1, "consent_gate_default": "open"}"#.utf8)
        XCTAssertFalse(store.apply(.updated(body: unexpected, etag: nil), appID: "app"))
        XCTAssertEqual(store.current, .fallback)
    }

    func testUnknownGateValueWaitsForConsent() throws {
        let body = Data(#"{"schema_version": 2, "consent_gate_default": {"analytics": "grandfather"}}"#.utf8)
        let config = try XCTUnwrap(SdkConfig(json: body))
        XCTAssertEqual(config.gateDefault(for: "analytics"), .closed)
        XCTAssertEqual(config.schemaVersion, 2)
    }
}

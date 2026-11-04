import XCTest
@testable import Detour

final class ConsentGateTests: XCTestCase {
    private let granted = DetourConsent(purposes: [DetourPurpose.analytics: true])
    private let denied = DetourConsent(purposes: [DetourPurpose.analytics: false])
    private let otherPurposeOnly = DetourConsent(purposes: [DetourPurpose.attribution: true])

    private func decision(
        sinceLaunch: DetourConsent? = nil,
        stored: DetourConsent? = nil,
        gate: ConsentGateDefault
    ) -> GateDecision {
        ConsentGate.decision(
            for: DetourPurpose.analytics,
            consentPassedThisLaunch: sinceLaunch,
            storedConsent: stored,
            gateDefault: gate
        )
    }

    func testWithoutConsentTheServerDefaultDecides() {
        XCTAssertEqual(decision(gate: .open), .send)
        XCTAssertEqual(decision(gate: .closed), .wait)
    }

    func testConsentFromThisLaunchDecidesWhateverTheDefault() {
        XCTAssertEqual(decision(sinceLaunch: granted, gate: .closed), .send)
        XCTAssertEqual(decision(sinceLaunch: denied, gate: .open), .drop)
        XCTAssertEqual(decision(sinceLaunch: otherPurposeOnly, gate: .open), .drop)
    }

    func testStoredRefusalBlocksOnColdStart() {
        XCTAssertEqual(decision(stored: denied, gate: .open), .drop)
        XCTAssertEqual(decision(stored: otherPurposeOnly, gate: .open), .drop)
    }

    func testStoredGrantDoesNotPassAClosedGateOnItsOwn() {
        XCTAssertEqual(decision(stored: granted, gate: .closed), .wait)
        XCTAssertEqual(decision(stored: granted, gate: .open), .send)
    }

    func testNewChoiceOnThisLaunchReplacesTheStoredOne() {
        XCTAssertEqual(decision(sinceLaunch: granted, stored: denied, gate: .closed), .send)
    }
}

final class DetourConsentTests: XCTestCase {
    func testWireFormatMatchesTheApiContract() throws {
        let consent = DetourConsent(
            purposes: [DetourPurpose.analytics: true, DetourPurpose.adNetworkSharing: false],
            timestamp: Date(timeIntervalSince1970: 1_760_443_200),
            consentTextRef: "cmp-v12",
            schemaVersion: 1,
            source: "cmp"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(consent)) as? [String: Any])

        XCTAssertEqual(json["purposes"] as? [String: Bool], ["analytics": true, "ad_network_sharing": false])
        XCTAssertEqual(json["timestamp"] as? String, "2025-10-14T12:00:00.000Z")
        XCTAssertEqual(json["consent_text_ref"] as? String, "cmp-v12")
        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["source"] as? String, "cmp")
        XCTAssertNil(json["region"])
    }

    func testStoredConsentDecodesBack() throws {
        let consent = DetourConsent(purposes: ["custom_purpose": true], timestamp: Date(timeIntervalSince1970: 1_760_443_200.5), region: "eea")
        let decoded = try JSONDecoder().decode(DetourConsent.self, from: JSONEncoder().encode(consent))
        XCTAssertEqual(decoded, consent)
    }

    func testEveryRequestCarriesTheConsentSnapshot() {
        let context = RequestContext(consentSnapshot: DetourConsent(purposes: [DetourPurpose.analytics: true]))
        let snapshot = context.dictionary["consent_snapshot"] as? [String: Any]
        XCTAssertEqual(snapshot?["purposes"] as? [String: Bool], ["analytics": true])
    }
}

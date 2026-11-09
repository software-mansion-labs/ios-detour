import XCTest
@testable import Detour

final class ConsentGateTests: XCTestCase {
    private let granted = DetourConsent(purposes: [DetourPurpose.analytics: true])
    private let denied = DetourConsent(purposes: [DetourPurpose.analytics: false])
    private let otherPurposeOnly = DetourConsent(purposes: [DetourPurpose.attribution: true])

    private func decision(
        sinceLaunch: DetourConsent? = nil,
        stored: DetourConsent? = nil,
        gate: ConsentGateDefault,
        isEnabled: Bool = true
    ) -> GateDecision {
        ConsentGate.decision(
            for: DetourPurpose.analytics,
            isEnabled: isEnabled,
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

    func testKillSwitchStopsEvenGrantedPurposes() {
        XCTAssertEqual(decision(sinceLaunch: granted, gate: .open, isEnabled: false), .drop)
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

final class ConsentResendTests: XCTestCase {
    private let firstSend = Date(timeIntervalSince1970: 1_760_443_200)
    private let now = Date(timeIntervalSince1970: 1_760_529_600)
    private lazy var stored = DetourConsent(
        purposes: [DetourPurpose.analytics: true],
        timestamp: firstSend,
        consentTextRef: "cmp-v12",
        schemaVersion: 1
    )
    private let unchanged = DetourConsent(purposes: [DetourPurpose.analytics: true], consentTextRef: "cmp-v12", schemaVersion: 1)

    private let deviceID = "device-a"

    private func prepare(
        _ consent: DetourConsent,
        confirmedDeviceID: String? = "device-a",
        now: Date? = nil
    ) -> (consent: DetourConsent, needsSend: Bool) {
        ConsentStore.prepare(consent, stored: stored, confirmedDeviceID: confirmedDeviceID, deviceID: deviceID, now: now ?? self.now)
    }

    func testUnchangedConfirmedChoiceIsNotSentAndKeepsItsTime() {
        let result = prepare(unchanged)
        XCTAssertFalse(result.needsSend)
        XCTAssertEqual(result.consent.timestamp, firstSend)
    }

    func testChangedChoiceIsSentDatedNow() {
        var refused = unchanged
        refused.purposes[DetourPurpose.analytics] = false
        var newText = unchanged
        newText.consentTextRef = "cmp-v13"

        for consent in [refused, newText] {
            let result = prepare(consent)
            XCTAssertTrue(result.needsSend)
            XCTAssertEqual(result.consent.timestamp, now)
        }
    }

    func testUnconfirmedChoiceIsSentAgainWithItsFirstTime() {
        let result = prepare(unchanged, confirmedDeviceID: nil)
        XCTAssertTrue(result.needsSend)
        XCTAssertEqual(result.consent.timestamp, firstSend)
    }

    func testChoiceConfirmedForAnotherDeviceIdIsSentAgain() {
        // An install restored from a backup: same stored consent, new device ID.
        let result = prepare(unchanged, confirmedDeviceID: "device-from-backup")
        XCTAssertTrue(result.needsSend)
        XCTAssertEqual(result.consent.timestamp, firstSend)
    }

    func testExplicitTimestampIsAlwaysSent() {
        var dated = unchanged
        dated.timestamp = now
        let result = prepare(dated)
        XCTAssertTrue(result.needsSend)
        XCTAssertEqual(result.consent.timestamp, now)
    }

    func testConfirmationMatchesTheStoredCopyOfTheSentChoice() throws {
        var changed = unchanged
        changed.purposes[DetourPurpose.attribution] = true
        let sent = prepare(changed, now: Date(timeIntervalSince1970: 1_760_529_600.123456)).consent
        let storedCopy = try JSONDecoder().decode(DetourConsent.self, from: JSONEncoder().encode(sent))
        XCTAssertTrue(ConsentStore.isStill(sent, stored: storedCopy))
        XCTAssertFalse(ConsentStore.isStill(sent, stored: stored))
    }

    func testFirstChoiceIsSent() {
        let result = ConsentStore.prepare(unchanged, stored: nil, confirmedDeviceID: nil, deviceID: deviceID, now: now)
        XCTAssertTrue(result.needsSend)
        XCTAssertEqual(result.consent.timestamp, now)
    }
}

final class ConsentBodyTests: XCTestCase {
    private let consent = DetourConsent(purposes: [DetourPurpose.analytics: true], timestamp: Date(timeIntervalSince1970: 1_760_443_200))

    func testEmptyConsentTextIsLeftOutButTheConsentIsKept() throws {
        let body = try XCTUnwrap(SdkNetwork.consentBody(consent, consentText: "", deviceID: "device", userID: nil))
        XCTAssertNil(body["consent_text"])
        XCTAssertNotNil(body["consent"])
    }

    func testConsentTextIsSent() throws {
        let body = try XCTUnwrap(SdkNetwork.consentBody(consent, consentText: "Notice", deviceID: "device", userID: nil))
        XCTAssertEqual(body["consent_text"] as? String, "Notice")
    }
}

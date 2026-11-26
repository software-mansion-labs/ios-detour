import Detour
import XCTest
@testable import DetourAttribution

final class ConversionValueSchemaTests: XCTestCase {
    // The example from the API contract, with the currency in the condition.
    private let schema = try! JSONDecoder().decode(ConversionValueSchema.self, from: Data("""
    {
      "version": 3,
      "rules": [
        { "event": "purchase", "condition": { "revenue_gte": 10, "currency": "USD" }, "fine": 42, "coarse": "high", "lock": false, "priority": 10 },
        { "event": "purchase", "fine": 20, "coarse": "medium", "lock": false, "priority": 5 },
        { "event": "tutorial_complete", "condition": { "count_gte": 2 }, "fine": 5, "coarse": "low", "lock": true, "priority": 1 },
        { "event": "purchase", "fine": 64, "priority": 99 }
      ]
    }
    """.utf8))

    private func purchase(_ revenue: Decimal, _ currency: String = "USD") -> DetourConversion {
        DetourConversion(name: "purchase", revenue: revenue, currency: currency, revenueType: .iap)
    }

    func testTheHighestFineAmongMatchingRulesWins() {
        XCTAssertEqual(schema.bestRule(for: purchase(15), count: 1)?.fine, 42)
        XCTAssertEqual(schema.bestRule(for: purchase(5), count: 1)?.fine, 20)
    }

    func testARevenueRuleMatchesOnlyItsCurrency() {
        XCTAssertEqual(schema.bestRule(for: purchase(15, "EUR"), count: 1)?.fine, 20)
    }

    func testACountRuleWaitsForEnoughConversions() {
        let tutorial = DetourConversion(name: "tutorial_complete", revenue: 0, currency: "USD", revenueType: .other)

        XCTAssertNil(schema.bestRule(for: tutorial, count: 1))
        XCTAssertEqual(schema.bestRule(for: tutorial, count: 2)?.lock, true)
    }

    func testPriorityBreaksATieOnFine() throws {
        let tied = try JSONDecoder().decode(ConversionValueSchema.self, from: Data("""
        { "version": 1, "rules": [
          { "event": "purchase", "fine": 7, "coarse": "low", "priority": 1 },
          { "event": "purchase", "fine": 7, "coarse": "high", "priority": 2 }
        ] }
        """.utf8))

        XCTAssertEqual(tied.bestRule(for: purchase(1), count: 1)?.coarse, .high)
    }

    func testNoActiveSchemaMatchesNothing() throws {
        let empty = try JSONDecoder().decode(ConversionValueSchema.self, from: Data(#"{ "version": null, "rules": [] }"#.utf8))

        XCTAssertNil(empty.bestRule(for: purchase(100), count: 1))
    }
}

@MainActor
final class PostbackCopyKeysTests: XCTestCase {
    func testBothKeysAreReportedWhenMissingOrEmpty() {
        XCTAssertEqual(
            DetourAttribution.missingPostbackCopyKeys(in: ["AttributionCopyEndpoint": ""]),
            ["NSAdvertisingAttributionReportEndpoint", "AttributionCopyEndpoint"]
        )
    }

    func testNothingIsReportedWithBothKeys() {
        let info = [
            "NSAdvertisingAttributionReportEndpoint": "https://godetour.dev",
            "AttributionCopyEndpoint": "https://godetour.dev",
        ]
        XCTAssertEqual(DetourAttribution.missingPostbackCopyKeys(in: info), [])
    }
}

@MainActor
final class ConversionValueStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ConversionValueStoreTests"
    private let schemaBody = Data(#"{ "version": 1, "rules": [{ "event": "purchase", "fine": 9 }] }"#.utf8)

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testANewSchemaIsKeptAcrossLaunchesAndANotModifiedResponseKeepsIt() {
        ConversionValueStore(defaults: defaults).apply(.updated(body: schemaBody, etag: "v1"))

        let nextLaunch = ConversionValueStore(defaults: defaults)
        nextLaunch.apply(.notModified)
        nextLaunch.apply(.failed)

        XCTAssertEqual(nextLaunch.schemaETag, "v1")
        XCTAssertEqual(nextLaunch.schema.rules.map(\.fine), [9])
    }

    func testTheValueOnlyGoesUp() {
        let store = ConversionValueStore(defaults: defaults)

        store.raiseHighestFine(to: 10, installID: "a")
        store.raiseHighestFine(to: 3, installID: "a")
        XCTAssertEqual(store.highestFine(installID: "a"), 10)
    }

    func testAnotherInstallStartsOver() {
        let store = ConversionValueStore(defaults: defaults)
        store.markRegistered(installID: "a")
        store.raiseHighestFine(to: 30, installID: "a")
        XCTAssertEqual(store.count("purchase", installID: "a"), 1)

        XCTAssertFalse(store.isRegistered(installID: "b"))
        XCTAssertEqual(store.highestFine(installID: "b"), -1)
        XCTAssertEqual(store.count("purchase", installID: "b"), 1)
    }
}

@MainActor
final class DetourAttributionRegistrationTests: XCTestCase {
    private final class FakeHost: AttributionHosting {
        var isAttributionAllowed = true
        let installID = "install"

        func fetchConversionValueSchema(etag: String?) async -> DetourFetchResult {
            .updated(body: Data(#"{ "version": 1, "rules": [{ "event": "purchase", "fine": 12, "coarse": "high" }] }"#.utf8), etag: "v1")
        }
    }

    @MainActor
    private final class FakeUpdater: PostbackUpdating {
        var registerResults: [Bool]
        var updateResults: [Bool]
        var registrations = 0
        var updates: [Int] = []
        var calls: [String] = []

        init(registerResults: [Bool], updateResults: [Bool] = []) {
            self.registerResults = registerResults
            self.updateResults = updateResults
        }

        func register() async -> Bool {
            registrations += 1
            // Gives a value update started next to it the chance to overtake it.
            for _ in 0 ..< 3 { await Task.yield() }
            calls.append("register")
            return registerResults.isEmpty ? true : registerResults.removeFirst()
        }

        func update(fine: Int, coarse: CoarseValue?, lock: Bool) async -> Bool {
            updates.append(fine)
            calls.append("update \(fine)")
            return updateResults.isEmpty ? true : updateResults.removeFirst()
        }
    }

    private let suiteName = "DetourAttributionRegistrationTests"
    private var store: ConversionValueStore!
    private let purchase = DetourConversion(name: "purchase", revenue: 5, currency: "USD", revenueType: .iap)

    override func setUp() async throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = ConversionValueStore(defaults: defaults)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // Lets the tasks started by the provider finish.
    private func settle() async {
        for _ in 0 ..< 20 { await Task.yield() }
    }

    func testAFailedRegistrationRunsAgainOnTheNextConversion() async {
        let updater = FakeUpdater(registerResults: [false, true])
        let attribution = DetourAttribution(store: store, updater: updater)

        attribution.start(with: FakeHost())
        await settle()
        XCTAssertFalse(store.isRegistered(installID: "install"))

        attribution.didLogConversion(purchase)
        await settle()
        XCTAssertEqual(updater.registrations, 2)
        XCTAssertTrue(store.isRegistered(installID: "install"))
        XCTAssertEqual(updater.calls, ["register", "register", "update 12"])
    }

    func testATakenValueRegistersTheAppSoTheNextLaunchDoesNotSendZero() async {
        let updater = FakeUpdater(registerResults: [false, false, false])
        DetourAttribution(store: store, updater: updater).start(with: FakeHost())
        await settle()
        let attribution = DetourAttribution(store: store, updater: updater)
        attribution.start(with: FakeHost())
        await settle()
        attribution.didLogConversion(purchase)
        await settle()
        XCTAssertEqual(updater.updates, [12])

        DetourAttribution(store: store, updater: updater).start(with: FakeHost())
        await settle()
        XCTAssertEqual(updater.registrations, 3)
        XCTAssertEqual(updater.updates, [12])
    }

    func testAValueSKAdNetworkRejectedIsSentAgain() async {
        let updater = FakeUpdater(registerResults: [], updateResults: [false, true])
        let attribution = DetourAttribution(store: store, updater: updater)
        attribution.start(with: FakeHost())
        await settle()

        attribution.didLogConversion(purchase)
        await settle()
        attribution.didLogConversion(purchase)
        await settle()
        attribution.didLogConversion(purchase)
        await settle()

        XCTAssertEqual(updater.updates, [12, 12])
    }

    func testNothingReachesSKAdNetworkWithoutConsent() async {
        let updater = FakeUpdater(registerResults: [])
        let attribution = DetourAttribution(store: store, updater: updater)
        let host = FakeHost()
        host.isAttributionAllowed = false

        attribution.start(with: host)
        await settle()

        XCTAssertEqual(updater.registrations, 0)
    }
}

final class AdvertisingIDTests: XCTestCase {
    func testAZeroIDFAIsNoIDFA() throws {
        let zero = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertNil(DetourAttribution.advertisingID(from: zero))
    }

    @MainActor
    func testAnAppForChildrenReadsNoIDFA() {
        let attribution = DetourAttribution(store: ConversionValueStore(), updater: ApplePostbackUpdater(), isChildDirected: true)
        XCTAssertNil(attribution.advertisingID())
    }

    func testTheIDFAIsSentLowercase() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6D92078A-8246-4BA4-AE5B-76104861E7DC"))
        XCTAssertEqual(DetourAttribution.advertisingID(from: id), "6d92078a-8246-4ba4-ae5b-76104861e7dc")
    }
}

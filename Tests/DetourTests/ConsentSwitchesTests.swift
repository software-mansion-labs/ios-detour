import XCTest
@testable import Detour

@MainActor
final class ConsentSwitchesTests: XCTestCase {
    private final class StartCountingProvider: DetourAttributionProvider, @unchecked Sendable {
        var starts = 0
        func didStart(_ host: DetourAttributionHost) { starts += 1 }
        func didLogConversion(_ conversion: DetourConversion) {}
        func attributionToken() async -> String? { nil }
    }

    private var warnings: [String] = []

    override func setUp() async throws {
        ConsentWarnings.resetForTests()
        ConsentWarnings.isDevelopment = true
        ConsentWarnings.write = { [weak self] in self?.warnings.append($0) }
    }

    override func tearDown() async throws {
        AttributionMode.register(nil)
        ConsentWarnings.resetForTests()
        ConsentWarnings.write = { DetourLogger.warn("Detour", $0) }
    }

    func testWorkWaitsForTheAttributionDecisionThenRunsOnce() {
        var runs = 0
        AttributionMode.whenDecided(isWaiting: true) { runs += 1 }
        AttributionMode.reevaluate(isWaiting: true)
        XCTAssertEqual(runs, 0)

        AttributionMode.reevaluate(isWaiting: false)
        AttributionMode.reevaluate(isWaiting: false)
        XCTAssertEqual(runs, 1)
    }

    func testWorkRunsAtOnceWhenTheGateDoesNotWait() {
        var runs = 0
        AttributionMode.whenDecided(isWaiting: false) { runs += 1 }
        XCTAssertEqual(runs, 1)
    }

    func testANewProviderDropsWorkWaitingForTheOldOne() {
        var runs = 0
        AttributionMode.whenDecided(isWaiting: true) { runs += 1 }
        AttributionMode.register(StartCountingProvider())
        AttributionMode.reevaluate(isWaiting: false)
        XCTAssertEqual(runs, 0)
    }

    func testEachWarningOnceInADevelopmentBuild() {
        ConsentWarnings.warnOnce("a", "first")
        ConsentWarnings.warnOnce("a", "again")
        ConsentWarnings.warnOnce("b", "other")
        XCTAssertEqual(warnings, ["[Detour:CONSENT] first", "[Detour:CONSENT] other"])
    }

    func testNoWarningInAProductionBuild() {
        ConsentWarnings.isDevelopment = false
        ConsentWarnings.warnOnce("a", "first")
        XCTAssertEqual(warnings, [])
    }

    func testTheProcessedLinkIsReportedOnce() {
        var reports = 0
        let report = LinkProcessedReport { reports += 1 }
        report.processed()
        report.processed()
        XCTAssertEqual(reports, 1)
        LinkProcessedReport(nil).processed()
    }

    func testStatusDecisionsUseTheContractNames() {
        XCTAssertEqual(DetourStatus.Decision(.send).rawValue, "send")
        XCTAssertEqual(DetourStatus.Decision(.wait).rawValue, "wait")
        XCTAssertEqual(DetourStatus.Decision(.drop).rawValue, "drop")
    }
}

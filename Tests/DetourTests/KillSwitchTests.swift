import XCTest
@testable import Detour

@MainActor
final class KillSwitchTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "KillSwitchTests"
    private let at = Date(timeIntervalSince1970: 1_760_445_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> InstallStore {
        InstallStore(directory: directory, defaults: defaults)
    }

    func testDisabledStateSurvivesRelaunchAndKeepsTheDeviceID() {
        let store = makeStore()
        let deviceID = store.deviceID
        XCTAssertTrue(store.setEnabled(false, at: at))

        let relaunched = makeStore()
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertEqual(relaunched.deviceID, deviceID)
    }

    func testRepeatedCallWithTheSameStateIsNotAChange() {
        let store = makeStore()
        XCTAssertFalse(store.setEnabled(true, at: at))
        XCTAssertNil(store.unreportedKillSwitch)

        XCTAssertTrue(store.setEnabled(false, at: at))
        XCTAssertFalse(store.setEnabled(false, at: at.addingTimeInterval(60)))
        XCTAssertEqual(store.unreportedKillSwitch?.at, at)
    }

    func testFileFromAnSdkWithoutTheKillSwitchKeepsItsDeviceID() throws {
        let deviceID = "3f2b8c1e-9d4a-4c55-8f0e-2a6b7c8d9e01"
        let file = directory.appendingPathComponent("Detour", isDirectory: true).appendingPathComponent("install.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"deviceID":"\#(deviceID)","firstLaunchHandled":true}"#.utf8).write(to: file)

        let store = makeStore()
        XCTAssertEqual(store.deviceID, deviceID)
        XCTAssertTrue(store.isEnabled)
        XCTAssertFalse(store.isFirstLaunch)
    }

    func testReporterSendsTheStateUntilConfirmed() async {
        let store = makeStore()
        _ = store.setEnabled(false, at: at)
        var sent: [Bool] = []
        var outcomes: [KillSwitchReporter.Outcome] = [.retry, .confirmed]
        var delays: [TimeInterval] = []
        let reporter = KillSwitchReporter(
            store: store,
            send: { enabled, date in
                XCTAssertEqual(date, self.at)
                sent.append(enabled)
                return outcomes.removeFirst()
            },
            sleep: { delays.append($0) }
        )

        await reporter.run()

        XCTAssertEqual(sent, [false, false])
        XCTAssertEqual(delays, [KillSwitchReporter.firstRetryDelay])
        XCTAssertNil(store.unreportedKillSwitch)
        XCTAssertNil(makeStore().unreportedKillSwitch)
    }

    func testChangeDuringARequestIsSentAfterIt() async {
        let store = makeStore()
        _ = store.setEnabled(false, at: at)
        var sent: [Bool] = []
        let reporter = KillSwitchReporter(store: store, send: { enabled, _ in
            sent.append(enabled)
            if sent.count == 1 {
                _ = store.setEnabled(true, at: self.at.addingTimeInterval(10))
            }
            return .confirmed
        })

        await reporter.run()

        XCTAssertEqual(sent, [false, true])
        XCTAssertNil(store.unreportedKillSwitch)
    }

    func testRejectedStateIsKeptForTheNextLaunch() async {
        let store = makeStore()
        _ = store.setEnabled(false, at: at)
        let reporter = KillSwitchReporter(store: store, send: { _, _ in .stop })

        await reporter.run()

        XCTAssertEqual(makeStore().unreportedKillSwitch?.enabled, false)
    }
}

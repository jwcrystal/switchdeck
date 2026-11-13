import XCTest
@testable import SwitchKit

final class KeepAwakeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "KeepAwakeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSystemOnlyByDefault() {
        let options = KeepAwakeSwitch.activityOptions(keepsDisplayOn: false)
        XCTAssertTrue(options.contains(.idleSystemSleepDisabled))
        XCTAssertFalse(options.contains(.idleDisplaySleepDisabled))
    }

    func testDisplayOptionAddsDisplayAssertion() {
        let options = KeepAwakeSwitch.activityOptions(keepsDisplayOn: true)
        XCTAssertTrue(options.contains(.idleSystemSleepDisabled))
        XCTAssertTrue(options.contains(.idleDisplaySleepDisabled))
    }

    func testDisplayOptionIsRemembered() {
        KeepAwakeSwitch(defaults: defaults).keepsDisplayOn = true
        XCTAssertTrue(KeepAwakeSwitch(defaults: defaults).keepsDisplayOn)
    }

    func testStartUsesDisplayOption() {
        let keepAwake = KeepAwakeSwitch(defaults: defaults)
        keepAwake.keepsDisplayOn = true
        keepAwake.start(minutes: nil)
        defer { keepAwake.stop() }
        XCTAssertEqual(keepAwake.activeOptions?.contains(.idleDisplaySleepDisabled), true)
    }

    func testTogglingWhileOnSwapsAssertionAndKeepsExpiry() {
        let keepAwake = KeepAwakeSwitch(defaults: defaults)
        keepAwake.start(minutes: 30)
        defer { keepAwake.stop() }
        let expiry = keepAwake.expiry
        XCTAssertEqual(keepAwake.activeOptions?.contains(.idleDisplaySleepDisabled), false)

        keepAwake.keepsDisplayOn = true

        XCTAssertTrue(keepAwake.isOn)
        XCTAssertEqual(keepAwake.activeOptions?.contains(.idleDisplaySleepDisabled), true)
        XCTAssertEqual(keepAwake.expiry, expiry)
    }

    func testTogglingWhileOffDoesNotStart() {
        let keepAwake = KeepAwakeSwitch(defaults: defaults)
        keepAwake.keepsDisplayOn = true
        XCTAssertFalse(keepAwake.isOn)
        XCTAssertNil(keepAwake.activeOptions)
    }

    func testStopClearsState() {
        let keepAwake = KeepAwakeSwitch(defaults: defaults)
        keepAwake.start(minutes: 5)
        keepAwake.stop()
        XCTAssertFalse(keepAwake.isOn)
        XCTAssertNil(keepAwake.expiry)
        XCTAssertNil(keepAwake.activeOptions)
    }
}

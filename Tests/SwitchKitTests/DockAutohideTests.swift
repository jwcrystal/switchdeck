import XCTest
@testable import SwitchKit

private final class StubDockPreferences: DockPreferences {
    var isAutohideOn: Bool
    var writeFails: Bool
    private(set) var lastWritten: Bool?
    private(set) var restartCount = 0

    init(isAutohideOn: Bool, writeFails: Bool = false) {
        self.isAutohideOn = isAutohideOn
        self.writeFails = writeFails
    }

    func autohide() -> Bool { isAutohideOn }

    func setAutohide(_ on: Bool) throws {
        if writeFails {
            throw SwitchDeckError.shell("write failed")
        }
        lastWritten = on
        isAutohideOn = on
    }

    func restartDock() {
        restartCount += 1
    }
}

final class DockAutohideTests: XCTestCase {
    func testToggleTurnsAutohideOn() throws {
        let preferences = StubDockPreferences(isAutohideOn: false)
        let dock = DockAutohideSwitch(preferences: preferences)

        try dock.toggle()

        XCTAssertEqual(preferences.lastWritten, true)
        XCTAssertTrue(dock.isOn)
    }

    func testToggleTurnsAutohideOff() throws {
        let preferences = StubDockPreferences(isAutohideOn: true)
        let dock = DockAutohideSwitch(preferences: preferences)

        try dock.toggle()

        XCTAssertEqual(preferences.lastWritten, false)
        XCTAssertFalse(dock.isOn)
    }

    func testSetRestartsTheDockAfterWriting() throws {
        let preferences = StubDockPreferences(isAutohideOn: false)
        let dock = DockAutohideSwitch(preferences: preferences)

        try dock.set(true)

        XCTAssertEqual(preferences.lastWritten, true)
        XCTAssertEqual(preferences.restartCount, 1)
    }

    func testFailedWriteDoesNotRestartTheDock() {
        let preferences = StubDockPreferences(isAutohideOn: false, writeFails: true)
        let dock = DockAutohideSwitch(preferences: preferences)

        XCTAssertThrowsError(try dock.set(true))
        XCTAssertNil(preferences.lastWritten)
        XCTAssertEqual(preferences.restartCount, 0)
    }
}

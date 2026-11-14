import XCTest
@testable import SwitchKit

final class MuteSwitchTests: XCTestCase {
    private final class StubMute: AudioMuteControl {
        var available: Bool
        var setSucceeds: Bool
        var muted: [AudioDirection: Bool] = [:]
        private(set) var writes: [(muted: Bool, direction: AudioDirection)] = []

        init(available: Bool = true, setSucceeds: Bool = true) {
            self.available = available
            self.setSucceeds = setSucceeds
        }

        func isMuted(_ direction: AudioDirection) -> Bool? {
            available ? (muted[direction] ?? false) : nil
        }

        func setMuted(_ muted: Bool, _ direction: AudioDirection) -> Bool {
            writes.append((muted, direction))
            guard available, setSucceeds else { return false }
            self.muted[direction] = muted
            return true
        }
    }

    func testToggleMutesAndUnmutesOutput() throws {
        let control = StubMute()
        let sound = MuteSwitch(direction: .output, control: control)

        XCTAssertTrue(sound.isAvailable)
        XCTAssertFalse(sound.isMuted)

        try sound.toggle()
        XCTAssertTrue(sound.isMuted)
        XCTAssertEqual(control.writes.map(\.muted), [true])
        XCTAssertEqual(control.writes.map(\.direction), [.output])

        try sound.toggle()
        XCTAssertFalse(sound.isMuted)
        XCTAssertEqual(control.writes.map(\.muted), [true, false])
    }

    func testToggleWritesInputDirection() throws {
        let control = StubMute()
        let microphone = MuteSwitch(direction: .input, control: control)

        try microphone.toggle()

        XCTAssertEqual(control.writes.count, 1)
        XCTAssertEqual(control.writes.first?.direction, .input)
        XCTAssertEqual(control.writes.first?.muted, true)
        XCTAssertTrue(microphone.isMuted)
    }

    func testUnavailableShowsSubtitleAndThrows() {
        let control = StubMute(available: false)
        let sound = MuteSwitch(direction: .output, control: control)

        XCTAssertFalse(sound.isAvailable)
        XCTAssertFalse(sound.isMuted)
        XCTAssertEqual(sound.subtitle, "Not available")
        XCTAssertThrowsError(try sound.toggle()) { error in
            XCTAssertEqual(
                (error as? SwitchDeckError)?.errorDescription,
                "This device can't be muted."
            )
        }
        XCTAssertTrue(control.writes.isEmpty)
    }

    func testAvailableHasNoSubtitle() {
        let sound = MuteSwitch(direction: .output, control: StubMute())
        XCTAssertNil(sound.subtitle)
    }

    func testFailedSetThrows() {
        let sound = MuteSwitch(direction: .input, control: StubMute(setSucceeds: false))

        XCTAssertThrowsError(try sound.toggle()) { error in
            XCTAssertEqual(
                (error as? SwitchDeckError)?.errorDescription,
                "This device can't be muted."
            )
        }
        XCTAssertFalse(sound.isMuted)
    }
}

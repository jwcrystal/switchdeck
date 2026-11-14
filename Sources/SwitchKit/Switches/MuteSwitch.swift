import Foundation

/// Mutes the system default output or input device.
///
/// The device is looked up on every read, so plugging in headphones or a USB
/// microphone moves the switch to the new device without any refresh.
public final class MuteSwitch {
    private let direction: AudioDirection
    private let control: AudioMuteControl

    public init(direction: AudioDirection, control: AudioMuteControl = CoreAudioMute()) {
        self.direction = direction
        self.control = control
    }

    /// False when the default device has no settable mute property.
    public var isAvailable: Bool {
        control.isMuted(direction) != nil
    }

    public var isMuted: Bool {
        control.isMuted(direction) ?? false
    }

    public var subtitle: String? {
        isAvailable ? nil : t("Not available")
    }

    public func toggle() throws {
        guard let muted = control.isMuted(direction) else {
            throw SwitchDeckError.message(t("This device can't be muted."))
        }
        guard control.setMuted(!muted, direction) else {
            throw SwitchDeckError.message(t("This device can't be muted."))
        }
    }
}

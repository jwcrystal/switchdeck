import CoreAudio
import Foundation

/// Which system default device a mute switch acts on.
public enum AudioDirection {
    case output
    case input
}

/// Reads and writes the mute property of the default output or input device.
public protocol AudioMuteControl {
    /// nil when there is no default device or it has no settable mute.
    func isMuted(_ direction: AudioDirection) -> Bool?
    /// false when the device could not be muted/unmuted.
    func setMuted(_ muted: Bool, _ direction: AudioDirection) -> Bool
}

/// The CoreAudio implementation, straight off `kAudioDevicePropertyMute`.
///
/// The default device is read on every call: headphones, displays and USB
/// interfaces come and go, and the previous device must not be kept around.
/// Stereo devices often expose mute only per channel, so element 0 is used when
/// it exists and channels 1 and 2 are the fallback.
public struct CoreAudioMute: AudioMuteControl {
    public init() {}

    public func isMuted(_ direction: AudioDirection) -> Bool? {
        guard let device = Self.defaultDevice(direction) else { return nil }
        let elements = Self.muteElements(device, direction)
        guard !elements.isEmpty,
              elements.contains(where: { Self.isSettable(device, direction, $0) })
        else { return nil }
        return elements.allSatisfy { Self.muteValue(device, direction, $0) == true }
    }

    public func setMuted(_ muted: Bool, _ direction: AudioDirection) -> Bool {
        guard let device = Self.defaultDevice(direction) else { return false }
        let elements = Self.muteElements(device, direction)
            .filter { Self.isSettable(device, direction, $0) }
        guard !elements.isEmpty else { return false }
        return elements.allSatisfy { Self.setMuteValue(muted, device, direction, $0) }
    }

    // MARK: - CoreAudio plumbing

    private static func defaultDevice(_ direction: AudioDirection) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: direction == .output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var id = AudioDeviceID(0)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != 0 else { return nil }
        return id
    }

    /// Main element first; per-channel mute is the common fallback on stereo devices.
    private static func muteElements(
        _ device: AudioDeviceID,
        _ direction: AudioDirection
    ) -> [AudioObjectPropertyElement] {
        let main = kAudioObjectPropertyElementMain
        if hasMute(device, direction, main) { return [main] }
        return [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].filter {
            hasMute(device, direction, $0)
        }
    }

    private static func address(
        _ direction: AudioDirection,
        _ element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: direction == .output
                ? kAudioDevicePropertyScopeOutput
                : kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private static func hasMute(
        _ device: AudioDeviceID,
        _ direction: AudioDirection,
        _ element: AudioObjectPropertyElement
    ) -> Bool {
        var address = address(direction, element)
        return AudioObjectHasProperty(device, &address)
    }

    private static func isSettable(
        _ device: AudioDeviceID,
        _ direction: AudioDirection,
        _ element: AudioObjectPropertyElement
    ) -> Bool {
        var address = address(direction, element)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else {
            return false
        }
        return settable.boolValue
    }

    private static func muteValue(
        _ device: AudioDeviceID,
        _ direction: AudioDirection,
        _ element: AudioObjectPropertyElement
    ) -> Bool? {
        var address = address(direction, element)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value = UInt32(0)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private static func setMuteValue(
        _ muted: Bool,
        _ device: AudioDeviceID,
        _ direction: AudioDirection,
        _ element: AudioObjectPropertyElement
    ) -> Bool {
        var address = address(direction, element)
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        ) == noErr
    }
}

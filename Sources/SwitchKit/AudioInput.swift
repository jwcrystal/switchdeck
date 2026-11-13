import CoreAudio
import Foundation

/// The microphones a recording can use, read straight from CoreAudio.
///
/// `AVAudioRecorder` always records from the system default input, so picking a
/// device means switching that default for the duration of the recording.
public enum AudioInput {
    public struct Device: Identifiable, Hashable {
        /// The device UID, which survives relaunches and re-plugs.
        public let id: String
        public let name: String
        let deviceID: AudioDeviceID

        public var isDefault: Bool { deviceID == AudioInput.defaultDeviceID() }
    }

    public static func devices() -> [Device] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        var seen = Set<String>()
        return ids.compactMap { id -> Device? in
            guard hasInput(id),
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName),
                  seen.insert(uid).inserted
            else { return nil }
            return Device(id: uid, name: name, deviceID: id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func defaultDeviceID() -> AudioDeviceID? {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var id = AudioDeviceID(0)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != 0 else { return nil }
        return id
    }

    @discardableResult
    public static func setDefaultDevice(_ id: AudioDeviceID) -> Bool {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &value
        ) == noErr
    }

    // MARK: - CoreAudio plumbing

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func string(
        _ id: AudioDeviceID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}

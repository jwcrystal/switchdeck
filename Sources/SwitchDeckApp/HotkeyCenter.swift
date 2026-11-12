import Carbon.HIToolbox
import Foundation
import SwitchKit

/// Registers system-wide shortcuts with Carbon.
///
/// Carbon's `RegisterEventHotKey` still works without Accessibility permission
/// (unlike `CGEventTap`), it fails with `eventHotKeyExistsErr` when another app
/// already owns the same combination, and the events arrive on the main thread.
final class HotkeyCenter {
    struct RegistrationFailure: LocalizedError {
        let binding: HotkeyBinding
        let status: OSStatus

        var errorDescription: String? {
            if status == OSStatus(eventHotKeyExistsErr) {
                return "\(binding.displayString) is already used by the system or another app."
            }
            return "\(binding.displayString) could not be registered (OSStatus \(status))."
        }
    }

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() {
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ binding: HotkeyBinding, action: @escaping () -> Void) throws {
        var reference: EventHotKeyRef?
        let id = nextID
        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_444B), id: id) // 'SWDK'

        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw RegistrationFailure(binding: binding, status: status)
        }

        nextID += 1
        hotKeyRefs.append(reference)
        actions[id] = action
    }

    func unregisterAll() {
        for reference in hotKeyRefs {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

private func hotkeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    Unmanaged<HotkeyCenter>.fromOpaque(userData)
        .takeUnretainedValue()
        .fire(hotKeyID.id)

    return noErr
}

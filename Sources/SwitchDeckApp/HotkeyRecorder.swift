import AppKit
import Carbon.HIToolbox
import SwitchKit

/// Turns an `NSEvent` from the shortcut recorder into a binding.
enum HotkeyRecorder {
    static func binding(from event: NSEvent) -> HotkeyBinding? {
        guard let label = keyLabel(for: event) else { return nil }
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        return HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= HotkeyBinding.commandModifier }
        if flags.contains(.option) { modifiers |= HotkeyBinding.optionModifier }
        if flags.contains(.control) { modifiers |= HotkeyBinding.controlModifier }
        if flags.contains(.shift) { modifiers |= HotkeyBinding.shiftModifier }
        return modifiers
    }

    /// Key code first, because `charactersIgnoringModifiers` returns odd values
    /// for function keys and arrows.
    static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 76: return "⌤"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 119: return "↘"
        case 121: return "⇟"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }

        guard let characters = event.charactersIgnoringModifiers,
              let first = characters.first,
              !first.isWhitespace,
              first != "\u{7F}"
        else {
            return nil
        }
        return characters.uppercased()
    }
}

/// Watches key presses inside this app while a shortcut is being recorded.
///
/// A local monitor only sees events delivered to SwitchDeck, so recording never
/// asks for Accessibility permission and never steals keys from other apps.
final class KeyCaptureMonitor {
    private var monitor: Any?
    private var onEvent: ((NSEvent) -> Bool)?

    func start(onEvent: @escaping (NSEvent) -> Bool) {
        stop()
        self.onEvent = onEvent
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let handler = self.onEvent else { return event }
            return handler(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onEvent = nil
    }

    deinit {
        stop()
    }
}

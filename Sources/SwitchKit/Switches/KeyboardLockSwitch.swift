import AppKit
import ApplicationServices

/// Blocks key presses system-wide with a `CGEventTap`.
///
/// Mouse keeps working, so the menu stays reachable and can unlock again. A
/// five-minute timer prevents a trapped keyboard if the user walks away.
///
/// Requires Accessibility permission; without it the tap cannot be created and
/// the switch reports why instead of silently doing nothing.
public final class KeyboardLockSwitch {
    public static let autoUnlockInterval: TimeInterval = 5 * 60

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var autoUnlockTimer: Timer?
    private var swallowedKeys = 0

    public init() {}

    public private(set) var isLocked = false

    public var subtitle: String? {
        guard isLocked else { return nil }
        return "Auto-unlock 5m"
    }

    public func lock() throws {
        guard !isLocked else { return }
        guard ensureAccessibility() else {
            throw SwitchDeckError.message(
                "SwitchDeck needs Accessibility permission to block the keyboard. Open SwitchDeck › Permissions… and grant it once — after that this switch works without asking again."
            )
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, _, _ in
                // Returning nil swallows the event.
                nil
            },
            userInfo: nil
        ) else {
            throw SwitchDeckError.message("Could not create the keyboard event tap.")
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw SwitchDeckError.message("Could not attach the keyboard event tap to the run loop.")
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isLocked = true

        autoUnlockTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoUnlockInterval,
            repeats: false
        ) { [weak self] _ in
            self?.unlock()
        }
    }

    public func unlock() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        isLocked = false
    }

    /// Checks only; never prompts. The one prompt happens in the setup window so
    /// using a switch cannot produce a dialog.
    private func ensureAccessibility() -> Bool {
        AXIsProcessTrusted()
    }
}

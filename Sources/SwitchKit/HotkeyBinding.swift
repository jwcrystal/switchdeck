import Foundation

/// A global shortcut: one key plus modifiers, stored exactly as Carbon wants it
/// so registration needs no translation at launch time.
///
/// `label` is the key cap recorded when the shortcut was set ("K", "←", "F5").
/// Keeping it means the menu does not have to translate a key code through the
/// current keyboard layout every time it opens.
public struct HotkeyBinding: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    public var modifiers: UInt32
    public var label: String

    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    public static let commandModifier: UInt32 = 1 << 8
    public static let shiftModifier: UInt32 = 1 << 9
    public static let optionModifier: UInt32 = 1 << 11
    public static let controlModifier: UInt32 = 1 << 12

    /// Canonical order: ⌃ ⌥ ⇧ ⌘, then the key.
    public var symbols: String {
        var result = ""
        if modifiers & Self.controlModifier != 0 { result += "⌃" }
        if modifiers & Self.optionModifier != 0 { result += "⌥" }
        if modifiers & Self.shiftModifier != 0 { result += "⇧" }
        if modifiers & Self.commandModifier != 0 { result += "⌘" }
        return result
    }

    public var displayString: String { symbols + label }

    /// A shortcut without ⌘, ⌥ or ⌃ would swallow ordinary typing.
    public var isUsable: Bool {
        modifiers & (Self.commandModifier | Self.optionModifier | Self.controlModifier) != 0
    }
}

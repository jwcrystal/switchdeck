import Foundation

/// One entry in the status-bar menu.
///
/// Everything a menu row needs lives here: how it is drawn, what state it is in,
/// and what happens when it is clicked. Keeping the row a value type means the
/// menu can be rebuilt freely without the switches knowing about AppKit.
public struct SwitchItem {
    public enum Kind {
        /// A system setting with an on/off state. Shows a checkmark when on.
        case toggle
        /// A one-shot action. Shows no checkmark.
        case action
    }

    /// An entry in the item's submenu, e.g. "Keep Awake › 1 hour".
    public struct MenuAction {
        public let title: String
        /// Read when the menu opens; true draws a checkmark next to the entry.
        public let isChecked: () -> Bool
        /// Draws a separator above the entry.
        public let startsSection: Bool
        public let perform: () throws -> Void

        public init(
            title: String,
            isChecked: @escaping () -> Bool = { false },
            startsSection: Bool = false,
            perform: @escaping () throws -> Void
        ) {
            self.title = title
            self.isChecked = isChecked
            self.startsSection = startsSection
            self.perform = perform
        }
    }

    public let id: String
    public let title: String
    public let symbolName: String
    public let kind: Kind
    /// Read synchronously when the menu opens. Must stay cheap.
    public let state: () -> Bool
    /// Optional grey, right-aligned text: "Until 18:30", "101 items".
    public let subtitle: () -> String?
    /// Empty means the item gets no submenu.
    public let actions: () -> [MenuAction]
    public let perform: () throws -> Void

    public init(
        id: String,
        title: String,
        symbolName: String,
        kind: Kind,
        state: @escaping () -> Bool = { false },
        subtitle: @escaping () -> String? = { nil },
        actions: @escaping () -> [MenuAction] = { [] },
        perform: @escaping () throws -> Void
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.kind = kind
        self.state = state
        self.subtitle = subtitle
        self.actions = actions
        self.perform = perform
    }
}

public enum SwitchDeckError: LocalizedError {
    case automation(String)
    case shell(String)
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .automation(let message): return message
        case .shell(let message): return message
        case .message(let message): return message
        }
    }

    /// Extra guidance shown under the error in the alert.
    public var recoveryHint: String? {
        if case .automation = self {
            return "SwitchDeck needs Automation permission for the app it is scripting. Grant it in System Settings › Privacy & Security › Automation, then try again."
        }
        return nil
    }
}

import AppKit

/// Clears the system pasteboard.
public struct EmptyPasteboardSwitch {
    public init() {}

    public var isEmpty: Bool {
        NSPasteboard.general.types?.isEmpty ?? true
    }

    public func empty() {
        NSPasteboard.general.clearContents()
    }
}

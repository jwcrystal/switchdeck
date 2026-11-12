import AppKit

/// Small floating panel shown while a scrolling capture runs. It sits above
/// the overlay, which ignores the mouse during the capture so scroll gestures
/// reach the window underneath.
@MainActor
final class ScrollHUD: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "Scrolling capture")
    private let detail = NSTextField(labelWithString: "0 px · scroll, then Done")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 348, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true

        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 348, height: 52))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 11
        material.layer?.masksToBounds = true
        contentView = material

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 14, y: 27, width: 160, height: 16)

        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 14, y: 10, width: 200, height: 14)

        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.keyEquivalent = ""
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        doneButton.frame = NSRect(x: 348 - 66, y: 12, width: 56, height: 28)

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.frame = NSRect(x: 348 - 66 - 70, y: 12, width: 64, height: 28)

        material.addSubview(titleLabel)
        material.addSubview(detail)
        material.addSubview(cancelButton)
        material.addSubview(doneButton)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(height: Int) {
        detail.stringValue = "\(height) px · scroll, then Done"
    }

    /// Puts the panel just outside the selection, inside the screen.
    func position(near selection: NSRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = frame.size
        var origin = NSPoint(
            x: selection.midX - size.width / 2,
            y: selection.minY - size.height - 10
        )
        if origin.y < visible.minY + 6 {
            origin.y = selection.maxY + 10
        }
        origin.x = min(max(visible.minX + 6, origin.x), visible.maxX - size.width - 6)
        origin.y = min(max(visible.minY + 6, origin.y), visible.maxY - size.height - 6)
        setFrameOrigin(origin)
    }

    @objc private func doneTapped() {
        onDone?()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

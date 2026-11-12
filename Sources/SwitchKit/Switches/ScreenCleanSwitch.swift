import AppKit

/// Darkens every display and locks the keyboard for cleaning the screen.
///
/// The overlay sits at the screen-saver level, so it covers the menu bar too.
/// A click reveals a card with the way out; pressing "Stop Clean" closes the
/// overlays and unlocks the keyboard. If Accessibility is missing the screen
/// still goes dark and only the keyboard lock is skipped.
public final class ScreenCleanSwitch {
    private let keyboard: KeyboardLockSwitch
    private var windows: [NSWindow] = []

    public init(keyboard: KeyboardLockSwitch) {
        self.keyboard = keyboard
    }

    public var isActive: Bool { !windows.isEmpty }

    public func start() {
        guard windows.isEmpty else { return }
        let keyboardLocked = (try? keyboard.lock()) != nil

        for screen in NSScreen.screens {
            let window = CleanWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false

            let view = ScreenCleanView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                keyboardLocked: keyboardLocked
            )
            view.onStop = { [weak self] in self?.stop() }
            window.contentView = view

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
    }

    public func stop() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        keyboard.unlock()
    }
}

private final class CleanWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Black canvas, with a soft card that appears on the first click.
private final class ScreenCleanView: NSView {
    var onStop: (() -> Void)?

    private let card = NSView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Screen Clean")
    private let bodyLabel: NSTextField
    private let button = NSButton(title: "Stop Clean", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "Click anywhere to show the exit button")

    private var revealed = false

    init(frame: NSRect, keyboardLocked: Bool) {
        bodyLabel = NSTextField(wrappingLabelWithString: keyboardLocked
            ? "The display is dark and the keyboard is locked.\nWipe the screen with a dry cloth, then press the button below."
            : "The display is dark.\nWipe the screen with a dry cloth, then press the button below.\n\nAccessibility permission is missing, so the keyboard is not locked.")
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        icon.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
        icon.contentTintColor = NSColor(white: 1, alpha: 0.9)
        icon.imageScaling = .scaleNone

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = NSColor(white: 1, alpha: 0.7)
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 0

        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
        button.target = self
        button.action = #selector(stopPressed)

        let stack = NSStackView(views: [icon, titleLabel, bodyLabel, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(18, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        card.layer?.cornerRadius = 20
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.alphaValue = 0
        card.isHidden = true
        card.addSubview(stack)
        addSubview(card)

        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor(white: 1, alpha: 0.4)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 380),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),

            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -56),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ScreenCleanView is created in code only")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        reveal()
    }

    private func reveal() {
        guard !revealed else { return }
        revealed = true
        card.isHidden = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            card.animator().alphaValue = 1
            hint.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.hint.isHidden = true
        }
    }

    @objc private func stopPressed() {
        onStop?()
    }
}

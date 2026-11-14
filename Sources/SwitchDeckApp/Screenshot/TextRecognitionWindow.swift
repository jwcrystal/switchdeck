import AppKit
import SwiftUI
import SwitchKit

/// The result window for text recognition: the captured image beside (or
/// above) the recognised text, which can be corrected before it is copied.
///
/// It is a non-activating panel so it becomes key straight away without
/// SwitchDeck having to take over as the active app, which macOS 14 may
/// refuse. The text is selected on open: `⌘↩` or `⌘C` copies it, typing
/// replaces it, `Esc` closes.
@MainActor
final class TextRecognitionWindowController: NSObject, NSWindowDelegate {
    private static let originKey = "TextRecognitionWindowOrigin"

    private var panel: RecognitionPanel?
    private var model: RecognitionTextModel?

    func show(image: NSImage, result: TextRecognizer.Result) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let layout = RecognitionLayout(image: image, screen: NSScreen.main)
        let model = RecognitionTextModel(text: Self.initialText(for: result))
        model.onClose = { [weak panel] in panel?.close() }
        self.model = model
        panel.onCopy = { [weak model] in model?.copyAndClose() }

        let view = TextRecognitionView(
            image: image,
            layout: layout,
            link: TextRecognizer.openableLink(in: result.codes),
            model: model
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(layout.windowSize)
        place(panel)

        panel.orderFrontRegardless()
        panel.makeKey()
        // The text view exists once SwiftUI has laid the panel out.
        DispatchQueue.main.async { [weak panel, weak model] in
            guard let panel, let textView = model?.textView else { return }
            panel.makeFirstResponder(textView)
            textView.selectAll(nil)
        }
    }

    /// Codes first (they are usually what was framed), then the text.
    static func initialText(for result: TextRecognizer.Result) -> String {
        [result.codes.joined(separator: "\n"), result.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Window

    private func makePanel() -> RecognitionPanel {
        let panel = RecognitionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = t("Recognize Text")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.minSize = NSSize(width: 480, height: 300)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    /// Where the user left it last time, if that spot is still on a screen;
    /// otherwise centred on the screen with the pointer.
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            let topLeft = NSPointFromString(stored)
            let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame.constrained(to: screen.visibleFrame), display: false)
                return
            }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.originKey)
        model = nil
    }
}

private extension NSRect {
    func constrained(to bounds: NSRect) -> NSRect {
        var frame = self
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = min(max(bounds.minX, frame.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(bounds.minY, frame.minY), bounds.maxY - frame.height)
        return frame
    }
}

/// A panel that can take key focus, closes on `Esc` and copies on `⌘↩`
/// even while the text view has focus.
final class RecognitionPanel: NSPanel {
    var onCopy: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

// MARK: - Layout

/// Wide captures (a line of text) stack the image above the text; others put
/// it beside the text. The window starts at a size that fits the image.
struct RecognitionLayout {
    let stacked: Bool
    let imageSize: CGSize
    let windowSize: NSSize

    init(image: NSImage, screen: NSScreen?) {
        let scale = screen?.backingScaleFactor ?? 2
        let points = CGSize(width: image.size.width / scale, height: image.size.height / scale)
        let visible = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let aspect = points.width / max(points.height, 1)

        stacked = aspect >= 1.6
        if stacked {
            let height = min(points.height, 220)
            let width = min(points.height > 0 ? points.width * height / points.height : points.width, 900)
            imageSize = CGSize(width: width, height: width / max(aspect, 0.01))
            windowSize = NSSize(
                width: min(max(imageSize.width + 48, 560), visible.width * 0.8),
                height: min(imageSize.height + 48 + 220 + 52, visible.height * 0.8)
            )
        } else {
            let height = min(points.height, 520, visible.height * 0.7)
            let width = min(points.width * height / max(points.height, 1), 420)
            imageSize = CGSize(width: width, height: width / max(aspect, 0.01))
            windowSize = NSSize(
                width: min(imageSize.width + 48 + 400, visible.width * 0.8),
                height: min(max(imageSize.height + 48 + 52, 360), visible.height * 0.8)
            )
        }
    }
}

// MARK: - Text

@MainActor
final class RecognitionTextModel: ObservableObject {
    @Published var text: String
    @Published var copied = false
    weak var textView: NSTextView?
    var onClose: (() -> Void)?

    init(text: String) {
        self.text = text
    }

    var counts: (lines: Int, characters: Int) { TextRecognizer.counts(text) }

    /// Replaces the text through the text view, so `⌘Z` can undo it.
    func joinLines() {
        let joined = TextRecognizer.joinLines(text)
        guard joined != text else { return }
        if let textView {
            let all = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.insertText(joined, replacementRange: all)
            textView.selectAll(nil)
        } else {
            text = joined
        }
    }

    /// Copies, shows "Copied" for a moment so the click registers, then closes.
    func copyAndClose() {
        guard !text.isEmpty, !copied else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.onClose?()
        }
    }
}

/// A plain-text `NSTextView`, which SwiftUI's `TextEditor` cannot select
/// programmatically or hand focus to.
private struct RecognitionTextView: NSViewRepresentable {
    @ObservedObject var model: RecognitionTextModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = model.text
        textView.delegate = context.coordinator
        model.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != model.text else { return }
        textView.string = model.text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: RecognitionTextModel
        init(model: RecognitionTextModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated { model.text = textView.string }
        }
    }
}

// MARK: - View

private struct TextRecognitionView: View {
    let image: NSImage
    let layout: RecognitionLayout
    let link: URL?
    @ObservedObject var model: RecognitionTextModel

    @AppStorage(ScreenshotPreferences.silentRecognitionKey) private var silent = false

    var body: some View {
        VStack(spacing: 0) {
            if layout.stacked {
                VStack(spacing: 0) {
                    imagePane
                        .frame(maxWidth: .infinity)
                        .frame(height: layout.imageSize.height + 32)
                    Divider()
                    textPane
                }
            } else {
                HStack(spacing: 0) {
                    imagePane
                        .frame(width: layout.imageSize.width + 32)
                        .frame(maxHeight: .infinity)
                    Divider()
                    textPane
                }
            }

            Divider()
            bottomBar
        }
    }

    private var imagePane: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: layout.imageSize.width, maxHeight: layout.imageSize.height)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var textPane: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RecognitionTextView(model: model)
                if model.text.isEmpty {
                    Text(t("No text found"))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                let counts = model.counts
                Text(tf("%d lines · %d characters", counts.lines, counts.characters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(t("Join Lines")) { model.joinLines() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.counts.lines < 2)
                    .help(t("Merge the lines into one paragraph: no space between Chinese characters, one between words."))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Toggle(t("Silent recognition next time"), isOn: $silent)
                .toggleStyle(.checkbox)
                .help(t("Copy the result and show a short preview instead of opening the result window."))
            Spacer()
            if let link {
                Button(t("Open Link")) {
                    NSWorkspace.shared.open(link)
                    model.onClose?()
                }
                .help(link.absoluteString)
            }
            Button(t("Close")) { model.onClose?() }
                .keyboardShortcut(.cancelAction)
            Button {
                model.copyAndClose()
            } label: {
                Text(model.copied ? t("Copied ✓") : t("Copy"))
                    .frame(minWidth: 64)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(model.text.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Top-of-screen notice after a silent recognition. It shows the start of the
/// copied text; clicking it opens the result window to correct it.
@MainActor
enum RecognitionToast {
    private static var panels: [NSPanel] = []

    static func preview(of text: String, limit: Int = 60) -> String {
        let flat = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }

    static func show(_ title: String, detail: String?, onClick: @escaping () -> Void) {
        let panel = ClickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: ToastView(title: title, detail: detail))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = host
        panel.onClick = { [weak panel] in
            onClick()
            if let panel { dismiss(panel) }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        panel.orderFrontRegardless()
        panels.append(panel)

        Task { @MainActor [weak panel] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if let panel { dismiss(panel) }
        }
    }

    private static func dismiss(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }

    private final class ClickablePanel: NSPanel {
        var onClick: (() -> Void)?
        override var canBecomeKey: Bool { false }
        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    private struct ToastView: View {
        let title: String
        let detail: String?

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

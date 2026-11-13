import AppKit
import SwiftUI
import SwitchKit

/// The result window for text recognition: the captured image beside the
/// recognised text, which can be corrected before it is copied.
@MainActor
final class TextRecognitionWindowController {
    private var window: NSWindow?

    func show(image: NSImage, result: TextRecognizer.Result) {
        let window = self.window ?? makeWindow()
        self.window = window

        let view = TextRecognitionView(
            image: image,
            initialText: Self.initialText(for: result),
            onCopy: { [weak window] text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                window?.close()
            },
            onClose: { [weak window] in window?.close() }
        )
        window.contentView = NSHostingView(rootView: view)

        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Codes first (they are usually what was framed), then the text.
    static func initialText(for result: TextRecognizer.Result) -> String {
        [result.codes.joined(separator: "\n"), result.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = t("Recognize Text")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 520, height: 300)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}

private struct TextRecognitionView: View {
    let image: NSImage
    let onCopy: (String) -> Void
    let onClose: () -> Void

    @State private var text: String
    @AppStorage(ScreenshotPreferences.silentRecognitionKey) private var silent = false

    init(image: NSImage, initialText: String, onCopy: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.onCopy = onCopy
        self.onClose = onClose
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(Color(nsColor: .underPageBackgroundColor))

                Divider()

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                    if text.isEmpty {
                        Text(t("No text found"))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            HStack(spacing: 10) {
                Toggle(t("Silent recognition next time"), isOn: $silent)
                    .toggleStyle(.checkbox)
                    .help(t("Copy the result and show a short preview instead of opening the result window."))
                Spacer()
                Button(t("Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(t("Copy")) { onCopy(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
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

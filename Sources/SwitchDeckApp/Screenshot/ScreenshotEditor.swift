import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case rectangle, ellipse, arrow, pen, text

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .arrow: return "arrow.up.right"
            case .pen: return "pencil.tip"
            case .text: return "textformat"
            }
        }

        var help: String {
            switch self {
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .arrow: return "Arrow"
            case .pen: return "Freehand"
            case .text: return "Text"
            }
        }
    }

    struct TextDraft {
        var point: CGPoint
        var text: String
    }

    let image: CGImage
    let preview: NSImage

    @Published var annotations: [Annotation] = []
    @Published var tool: Tool = .rectangle
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 0.004
    @Published var draft: Annotation?
    @Published var textDraft: TextDraft?

    private var pinned: [NSWindow] = []

    init(image: CGImage) {
        self.image = image
        self.preview = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    // MARK: - Editing

    func commit(_ shape: Annotation.Shape) {
        annotations.append(Annotation(shape: shape, color: color, lineWidth: lineWidth))
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func commitText() {
        guard let draft = textDraft else { return }
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            commit(.text(trimmed, at: draft.point))
        }
        textDraft = nil
    }

    // MARK: - Output

    func composedImage() -> NSImage {
        AnnotationRenderer.render(base: image, annotations: annotations)
    }

    func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([composedImage()])
    }

    func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot \(Self.stamp()).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = composedImage().tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else {
            present("The image could not be encoded as PNG.")
            return
        }

        do {
            try data.write(to: url)
        } catch {
            present(error.localizedDescription)
        }
    }

    func pin() {
        let rendered = composedImage()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxWidth = screen.visibleFrame.width * 0.55
        let scale = min(1, maxWidth / rendered.size.width)
        let size = NSSize(
            width: max(80, rendered.size.width * scale),
            height: max(60, rendered.size.height * scale)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = rendered
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = imageView

        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2
        )
        window.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + size.height))
        window.makeKeyAndOrderFront(nil)

        pinned.append(window)
    }

    private func present(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot"
        alert.informativeText = message
        alert.runModal()
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}

struct ScreenshotEditorView: View {
    @ObservedObject var model: EditorModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            canvas
                .padding(10)

            Divider()
                .opacity(0.6)

            bottomBar
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        }
        .onExitCommand(perform: onClose)
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            ForEach(EditorModel.Tool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.tool == tool ? Color.accentColor.opacity(0.14) : .clear)
                        )
                        .foregroundStyle(model.tool == tool ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(tool.help)
            }

            Divider().frame(height: 18)

            ForEach(Annotation.palette, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(model.color == color ? 0.55 : 0.12), lineWidth: 2)
                    }
                    .padding(3)
                    .contentShape(Circle())
                    .onTapGesture { model.color = color }
            }

            Divider().frame(height: 18)

            thicknessButton(0.003, lineWidth: 1.4)
            thicknessButton(0.006, lineWidth: 3.0)

            Spacer(minLength: 10)

            iconButton("arrow.uturn.backward", help: "Undo (⌘Z)") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
            iconButton("doc.on.doc", help: "Copy (⌘C)") { model.copyToPasteboard() }
                .keyboardShortcut("c", modifiers: .command)
            iconButton("pin", help: "Pin on screen") { model.pin() }

            Divider().frame(height: 18)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Close (Esc)")

            Button {
                model.save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save PNG (⌘S)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func thicknessButton(_ width: CGFloat, lineWidth: CGFloat) -> some View {
        Button {
            model.lineWidth = width
        } label: {
            Capsule()
                .fill(model.lineWidth == width ? Color.accentColor : Color.secondary)
                .frame(width: 16, height: lineWidth)
                .frame(width: 26, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.lineWidth == width ? Color.accentColor.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(width < 0.005 ? "Thin line" : "Thick line")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                Image(nsImage: model.preview)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)

                AnnotationCanvas(model: model, displaySize: fitted)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(model.image.width) × \(model.image.height)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let image = model.pixelSize
        guard image.width > 0, image.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }

        let imageAspect = image.width / image.height
        let containerAspect = container.width / container.height

        if imageAspect > containerAspect {
            return CGSize(width: container.width, height: container.width / imageAspect)
        }
        return CGSize(width: container.height * imageAspect, height: container.height)
    }
}

private struct AnnotationCanvas: View {
    @ObservedObject var model: EditorModel
    let displaySize: CGSize

    @State private var startPoint: CGPoint?
    @State private var penPoints: [CGPoint] = []
    @FocusState private var textFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                for annotation in model.annotations {
                    draw(annotation, in: &context, size: size)
                }
                if let draft = model.draft {
                    draw(draft, in: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = normalize(value.location)
                    guard displaySize.width > 0, displaySize.height > 0 else { return }

                    switch model.tool {
                    case .text:
                        break
                    case .pen:
                        if startPoint == nil {
                            startPoint = normalize(value.startLocation)
                            penPoints = []
                        }
                        penPoints.append(point)
                        model.draft = Annotation(shape: .pen(points: penPoints), color: model.color, lineWidth: model.lineWidth)
                    case .rectangle, .ellipse, .arrow:
                        if startPoint == nil {
                            startPoint = normalize(value.startLocation)
                        }
                        guard let start = startPoint else { return }
                        let shape: Annotation.Shape
                        switch model.tool {
                        case .rectangle: shape = .rectangle(from: start, to: point)
                        case .ellipse: shape = .ellipse(from: start, to: point)
                        default: shape = .arrow(from: start, to: point)
                        }
                        model.draft = Annotation(shape: shape, color: model.color, lineWidth: model.lineWidth)
                    }
                }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    let start = startPoint ?? normalize(value.startLocation)
                    let end = normalize(value.location)

                    defer {
                        startPoint = nil
                        penPoints = []
                        model.draft = nil
                    }

                    if model.tool == .text {
                        if moved < 4 {
                            model.textDraft = .init(point: end, text: "")
                        }
                        return
                    }

                    guard moved >= 3 else { return }

                    switch model.tool {
                    case .rectangle:
                        model.commit(.rectangle(from: start, to: end))
                    case .ellipse:
                        model.commit(.ellipse(from: start, to: end))
                    case .arrow:
                        model.commit(.arrow(from: start, to: end))
                    case .pen:
                        model.commit(.pen(points: penPoints))
                    case .text:
                        break
                    }
                }
            )

            if let draft = model.textDraft {
                TextField("Text", text: Binding(
                    get: { model.textDraft?.text ?? "" },
                    set: { model.textDraft?.text = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .position(
                    x: draft.point.x * displaySize.width,
                    y: max(16, draft.point.y * displaySize.height - 16)
                )
                .focused($textFocused)
                .onSubmit { model.commitText() }
                .onAppear { textFocused = true }
            }
        }
    }

    private func normalize(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x / max(1, displaySize.width))),
            y: min(1, max(0, point.y / max(1, displaySize.height)))
        )
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, size: CGSize) {
        let color = annotation.color
        let lineWidth = max(1, annotation.lineWidth * size.width)

        func scale(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }

        switch annotation.shape {
        case .rectangle(let from, let to):
            let a = scale(from)
            let b = scale(to)
            let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized
            context.stroke(Path(rect), with: .color(color), lineWidth: lineWidth)

        case .ellipse(let from, let to):
            let a = scale(from)
            let b = scale(to)
            let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lineWidth)

        case .arrow(let from, let to):
            let a = scale(from)
            let b = scale(to)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(lineWidth * 3.2, 10)
            var headPath = Path()
            headPath.move(to: b)
            headPath.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
            headPath.move(to: b)
            headPath.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
            context.stroke(headPath, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .pen(let points):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: scale(first))
            for point in points.dropFirst() {
                path.addLine(to: scale(point))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        case .text(let text, let at):
            let resolved = context.resolve(
                Text(text)
                    .font(.system(size: max(12, size.width * 0.022), weight: .semibold))
                    .foregroundColor(color)
            )
            context.draw(resolved, at: scale(at), anchor: .topLeading)
        }
    }
}

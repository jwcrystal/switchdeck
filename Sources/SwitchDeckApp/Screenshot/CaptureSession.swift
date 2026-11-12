import SwiftUI

/// State for the in-place capture editor: the toolbar that sits under the
/// selection, plus the annotations drawn on it.
@MainActor
final class CaptureSession: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case select, rectangle, ellipse, line, arrow, pen, highlighter, text, number, mosaic, blur

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .select: return "cursorarrow"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.up.right"
            case .pen: return "pencil.tip"
            case .highlighter: return "highlighter"
            case .text: return "textformat"
            case .number: return "number.circle"
            case .mosaic: return "square.grid.3x3"
            case .blur: return "aqi.medium"
            }
        }

        var help: String {
            switch self {
            case .select: return "Select and move (⌫ deletes)"
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .line: return "Line"
            case .arrow: return "Arrow"
            case .pen: return "Freehand"
            case .highlighter: return "Highlighter"
            case .text: return "Text"
            case .number: return "Number"
            case .mosaic: return "Mosaic"
            case .blur: return "Blur"
            }
        }
    }

    enum Output {
        case copy
        case save
        case pin
    }

    @Published var tool: Tool = .select {
        didSet {
            if tool != .select {
                selectionIndex = nil
            }
        }
    }
    @Published var selectionIndex: Int?
    @Published var toolbarVisible = true
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 0.004
    @Published var textScale: CGFloat = 0.022
    @Published var textBubble = false
    @Published var arrowStyle: ArrowStyle = .straight
    @Published var annotations: [Annotation] = []
    @Published var watermarkEnabled = false
    @Published var watermarkHidden = false
    @Published var watermarkPlacement: AnnotationRenderer.WatermarkOptions.Placement = .bottomRight
    @Published var watermarkScale: CGFloat = 0.02
    @Published var watermarkRotation: CGFloat = 0
    @Published var watermarkOpacity: CGFloat = 0.6
    @Published var watermarkColor: Color = .white

    @Published var watermarkText: String = {
        let name = NSFullUserName()
        return name.isEmpty ? "SwitchDeck" : name
    }()

    var watermarkOptions: AnnotationRenderer.WatermarkOptions? {
        guard watermarkEnabled else { return nil }
        return .init(
            text: watermarkText,
            placement: watermarkPlacement,
            scale: watermarkScale,
            rotation: watermarkRotation,
            opacity: watermarkOpacity,
            color: NSColor(watermarkColor)
        )
    }

    var onUndo: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onPin: () -> Void = {}
    var onClose: () -> Void = {}

    var canUndo: Bool { !annotations.isEmpty }
}

/// Everything the overlay hands to the coordinator when the user finishes.
struct CapturePayload {
    let rect: CGRect
    let screen: NSScreen
    let annotations: [Annotation]
    let base: CGImage?
    /// Watermark to keep (also when it is hidden on the image).
    let watermark: AnnotationRenderer.WatermarkOptions?
    /// False when the watermark should be invisible but still recorded.
    let watermarkVisible: Bool
}

struct CaptureToolbarView: View {
    @ObservedObject var session: CaptureSession
    @State private var showWatermarkSettings = false

    var body: some View {
        HStack(spacing: 5) {
            Button {
                session.tool = .select
            } label: {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(session.tool == .select ? Color.accentColor.opacity(0.14) : .clear)
                    )
                    .foregroundStyle(session.tool == .select ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Select and move (⌫ deletes)")

            shapesMenu
            drawMenu
            textMenu
            effectsMenu

            Divider().frame(height: 18)

            ForEach(Annotation.palette, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle().strokeBorder(
                            Color.primary.opacity(session.color == color ? 0.55 : 0.12),
                            lineWidth: 2
                        )
                    }
                    .padding(2)
                    .contentShape(Circle())
                    .onTapGesture { session.color = color }
            }

            Divider().frame(height: 18)

            thickness(0.003, width: 1.4)
            thickness(0.006, width: 3.0)

            Divider().frame(height: 18)

            watermarkButton

            Divider().frame(height: 18)

            icon("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: session.canUndo, action: session.onUndo)
            icon("doc.on.doc", help: "Copy (↩)", action: session.onCopy)
            icon("square.and.arrow.down", help: "Save (Space)", action: session.onSave)
            icon("pin", help: "Pin (P)", action: session.onPin)
            icon("chevron.down", help: "Hide the toolbar (Tab)") { session.toolbarVisible = false }
            icon("xmark", help: "Close (Esc)", action: session.onClose)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .fixedSize()
    }

    private func thickness(_ value: CGFloat, width: CGFloat) -> some View {
        Button {
            session.lineWidth = value
        } label: {
            Capsule()
                .fill(session.lineWidth == value ? Color.accentColor : Color.secondary)
                .frame(width: 15, height: width)
                .frame(width: 24, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(session.lineWidth == value ? Color.accentColor.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(width < 2 ? "Thin line" : "Thick line")
    }

    // MARK: - Tool groups

    private var shapesMenu: some View {
        Menu {
            ForEach([CaptureSession.Tool.rectangle, .ellipse, .line, .arrow]) { tool in
                Button {
                    session.tool = tool
                } label: {
                    Label(tool.help, systemImage: tool.symbol)
                }
            }
            Divider()
            Picker("Arrow style", selection: $session.arrowStyle) {
                Text("Straight").tag(ArrowStyle.straight)
                Text("Curved").tag(ArrowStyle.curved)
                Text("Elbow").tag(ArrowStyle.elbow)
            }
        } label: {
            groupLabel([.rectangle, .ellipse, .line, .arrow], fallback: "rectangle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Shapes and arrow style")
    }

    private var drawMenu: some View {
        Menu {
            ForEach([CaptureSession.Tool.pen, .highlighter]) { tool in
                Button {
                    session.tool = tool
                } label: {
                    Label(tool.help, systemImage: tool.symbol)
                }
            }
        } label: {
            groupLabel([.pen, .highlighter], fallback: "pencil.tip")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Freehand and highlighter")
    }

    private var textMenu: some View {
        Menu {
            ForEach([CaptureSession.Tool.text, .number]) { tool in
                Button {
                    session.tool = tool
                } label: {
                    Label(tool.help, systemImage: tool.symbol)
                }
            }
            Divider()
            Picker("Text size", selection: $session.textScale) {
                Text("Small").tag(CGFloat(0.016))
                Text("Medium").tag(CGFloat(0.022))
                Text("Large").tag(CGFloat(0.030))
            }
            Toggle("Bubble background", isOn: $session.textBubble)
        } label: {
            groupLabel([.text, .number], fallback: "textformat")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Text, numbers, size and bubble")
    }

    private var effectsMenu: some View {
        Menu {
            ForEach([CaptureSession.Tool.mosaic, .blur]) { tool in
                Button {
                    session.tool = tool
                } label: {
                    Label(tool.help, systemImage: tool.symbol)
                }
            }
        } label: {
            groupLabel([.mosaic, .blur], fallback: "square.grid.3x3")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Mosaic and blur")
    }

    private func groupLabel(_ tools: [CaptureSession.Tool], fallback: String) -> some View {
        let active = tools.contains(session.tool)
        return HStack(spacing: 1) {
            Image(systemName: active ? session.tool.symbol : fallback)
                .font(.system(size: 12.5, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .frame(width: 32, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? Color.accentColor.opacity(0.14) : .clear)
        )
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    private var textSizeButton: some View {
        Button {
            switch session.textScale {
            case ..<0.019: session.textScale = 0.022
            case ..<0.026: session.textScale = 0.030
            default: session.textScale = 0.016
            }
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 24, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Text size (S / M / L)")
    }

    private var bubbleButton: some View {
        Button {
            session.textBubble.toggle()
        } label: {
            Image(systemName: "bubble.left")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 24, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(session.textBubble ? Color.accentColor.opacity(0.14) : .clear)
                )
                .foregroundStyle(session.textBubble ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("Filled bubble behind the text")
    }

    private func arrowStyleButton(_ style: ArrowStyle, symbol: String) -> some View {
        Button {
            session.arrowStyle = style
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 24, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(session.arrowStyle == style ? Color.accentColor.opacity(0.14) : .clear)
                )
                .foregroundStyle(session.arrowStyle == style ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(style == .straight ? "Straight arrow" : style == .curved ? "Curved arrow" : "Elbow arrow")
    }

    private var watermarkButton: some View {
        HStack(spacing: 2) {
            Button {
                session.watermarkEnabled.toggle()
                if !session.watermarkEnabled { session.watermarkHidden = false }
            } label: {
                Image(systemName: "signature")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 24, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(session.watermarkEnabled ? Color.accentColor.opacity(0.14) : .clear)
                    )
                    .foregroundStyle(session.watermarkEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Watermark: \(session.watermarkText)")

            if session.watermarkEnabled {
                Button {
                    session.watermarkHidden.toggle()
                } label: {
                    Image(systemName: session.watermarkHidden ? "eye.slash" : "eye")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 24, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.watermarkHidden ? Color.orange.opacity(0.16) : .clear)
                        )
                        .foregroundStyle(session.watermarkHidden ? Color.orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(session.watermarkHidden
                    ? "Watermark hidden; text is kept in the file metadata"
                    : "Hide the watermark but keep its text")

                Button {
                    showWatermarkSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Watermark position, size, rotation and opacity")
                .popover(isPresented: $showWatermarkSettings, arrowEdge: .bottom) {
                    WatermarkSettingsView(session: session)
                }
            }
        }
    }

    private func icon(
        _ symbol: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .help(help)
    }
}

private struct WatermarkSettingsView: View {
    @ObservedObject var session: CaptureSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watermark")
                .font(.headline)

            TextField("Watermark text", text: $session.watermarkText)
                .textFieldStyle(.roundedBorder)

            Picker("Position", selection: $session.watermarkPlacement) {
                ForEach(AnnotationRenderer.WatermarkOptions.Placement.allCases) { placement in
                    Label(placement.title, systemImage: placement.symbol).tag(placement)
                }
            }
            .pickerStyle(.menu)

            sliderRow(
                "Size",
                value: $session.watermarkScale,
                range: 0.01...0.06,
                text: String(format: "%.1f%%", session.watermarkScale * 100)
            )

            sliderRow(
                "Angle",
                value: $session.watermarkRotation,
                range: -90...90,
                text: "\(Int(session.watermarkRotation))°"
            )

            sliderRow(
                "Opacity",
                value: $session.watermarkOpacity,
                range: 0.15...1,
                text: "\(Int(session.watermarkOpacity * 100))%"
            )

            HStack(spacing: 8) {
                Text("Color")
                    .frame(width: 54, alignment: .leading)
                    .foregroundStyle(.secondary)

                ForEach(Self.palette, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().strokeBorder(
                                Color.primary.opacity(session.watermarkColor == color ? 0.6 : 0.12),
                                lineWidth: 2
                            )
                        }
                        .padding(2)
                        .contentShape(Circle())
                        .onTapGesture { session.watermarkColor = color }
                }
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private static let palette: [Color] = [.white, .black, .red, .yellow, .blue]

    private func sliderRow(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .frame(width: 54, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func sizeButton(_ scale: CGFloat, _ title: String) -> some View {
        Button(title) {
            session.watermarkScale = scale
        }
        .buttonStyle(.bordered)
        .tint(session.watermarkScale == scale ? .accentColor : nil)
    }

}

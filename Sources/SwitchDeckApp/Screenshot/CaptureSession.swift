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

        /// Tools whose variants live in a menu on the tool itself.
        var hasOptions: Bool {
            switch self {
            case .rectangle, .ellipse, .arrow, .highlighter, .text, .number, .mosaic, .blur:
                return true
            case .select, .line, .pen:
                return false
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
    @Published var shapeFilled = false
    @Published var mosaicBlock: CGFloat = 14
    @Published var numberStyle: NumberStyle = .circle
    @Published var highlighterAlpha: CGFloat = 0.32
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
    var onScroll: () -> Void = {}
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
    @State private var showColors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            mainRow
            if session.tool != .select {
                optionsRow
            }
        }
        .fixedSize()
    }

    private var mainRow: some View {
        HStack(spacing: 5) {
            ForEach(CaptureSession.Tool.allCases) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 18)

            watermarkButton

            Divider().frame(height: 18)

            icon("scroll", help: "Scrolling capture", action: session.onScroll)
            icon("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: session.canUndo, action: session.onUndo)
            icon("doc.on.doc", help: "Copy (↩)", action: session.onCopy)
            icon("square.and.arrow.down", help: "Save (Space)", action: session.onSave)
            icon("pin", help: "Pin (P)", action: session.onPin)
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

    private func toolButton(_ tool: CaptureSession.Tool) -> some View {
        let active = session.tool == tool
        return Button {
            session.tool = active ? .select : tool
            showColors = false
        } label: {
            Image(systemName: tool == .arrow ? arrowSymbol : tool.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.14) : .clear)
                )
                .foregroundStyle(active ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(tool.help)
        .accessibilityLabel(tool.help)
    }

    private var optionsRow: some View {
        HStack(spacing: 5) {
            if session.tool != .mosaic && session.tool != .blur {
                Button { showColors.toggle() } label: {
                    Circle().fill(session.color).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Color")
                .accessibilityLabel("Annotation color")
                .popover(isPresented: $showColors, arrowEdge: .bottom) {
                    HStack(spacing: 9) {
                        ForEach(Annotation.palette, id: \.self) { color in
                            Button { session.color = color; showColors = false } label: {
                                Circle().fill(color).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(session.color == color ? 0.7 : 0.15), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.description)
                        }
                    }.padding(12)
                }
                Divider().frame(height: 18)
            }
            toolOptions
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 7, y: 3)
        .padding(.leading, min(CGFloat(CaptureSession.Tool.allCases.firstIndex(of: session.tool) ?? 0) * 31, 150))
    }

    @ViewBuilder private var toolOptions: some View {
        let tool = session.tool
        switch tool {
        case .arrow:
            ForEach([ArrowStyle.straight, .curved, .elbow, .sCurve], id: \.self) { style in
                optionButton(style.title, selected: session.arrowStyle == style) { session.arrowStyle = style } label: {
                    ArrowOptionIcon(style: style).stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 24, height: 20)
                }
            }
            lineWidthSlider
        case .rectangle, .ellipse:
            optionIcon(tool == .ellipse ? "circle" : "rectangle", "Outline", selected: !session.shapeFilled) { session.shapeFilled = false }
            optionIcon(tool == .ellipse ? "circle.fill" : "rectangle.fill", "Filled", selected: session.shapeFilled) { session.shapeFilled = true }
            lineWidthSlider
        case .text:
            ForEach([CGFloat(0.016), 0.022, 0.030], id: \.self) { size in
                optionButton("Text size \(Int(size * 1000))", selected: session.textScale == size) { session.textScale = size } label: {
                    Text("A").font(.system(size: size * 600 + 4, weight: .medium))
                }
            }
            Divider().frame(height: 18)
            optionIcon("text.bubble", "Bubble background", selected: session.textBubble) { session.textBubble.toggle() }
        case .number:
            optionIcon("1.circle", "Circle marker", selected: session.numberStyle == .circle) { session.numberStyle = .circle }
            optionIcon("1.square", "Square marker", selected: session.numberStyle == .square) { session.numberStyle = .square }
        case .mosaic, .blur:
            Image(systemName: tool.symbol).frame(width: 26)
            optionSlider("Strength", value: $session.mosaicBlock, range: 6...32)
        case .highlighter:
            lineWidthSlider
            Image(systemName: "circle.lefthalf.filled").frame(width: 22)
            optionSlider("Opacity", value: $session.highlighterAlpha, range: 0.15...0.7)
        case .line, .pen:
            lineWidthSlider
        case .select:
            EmptyView()
        }
    }

    private var lineWidthSlider: some View {
        HStack(spacing: 3) {
            Divider().frame(height: 18)
            Image(systemName: "lineweight").frame(width: 23)
            optionSlider("Line width", value: $session.lineWidth, range: 0.0015...0.016)
        }
    }

    private func optionSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        Slider(value: value, in: range).controlSize(.mini).frame(width: 90)
            .help(title).accessibilityLabel(title)
    }

    private func optionIcon(_ symbol: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        optionButton(title, selected: selected, action: action) {
            Image(systemName: symbol).font(.system(size: 15))
        }
    }

    private func optionButton<Label: View>(_ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label().frame(width: 28, height: 26)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor.opacity(0.14) : .clear))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    // MARK: - Tool options

    private var arrowSymbol: String {
        switch session.arrowStyle {
        case .straight: return "arrow.right"
        case .curved: return "arrow.up.right"
        case .elbow: return "arrow.turn.right.down"
        case .sCurve: return "arrow.up.forward"
        }
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

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

        /// Drawing tools expose the contextual row below the main toolbar.
        var hasOptions: Bool {
            self != .select
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
    @Published var defaultStyle = AnnotationStyle()
    @Published var scrollingDirection: ScrollingCapture.Direction = .vertical
    @Published var annotations: [Annotation] = [] {
        didSet { refreshHistoryAvailability() }
    }
    @Published var watermarkEnabled = ScreenshotPreferences.watermarkOnByDefault
    @Published var watermarkHidden = false
    @Published var watermarkPlacement: AnnotationRenderer.WatermarkOptions.Placement = .bottomRight
    @Published var watermarkScale: CGFloat = 0.02
    @Published var watermarkRotation: CGFloat = 0
    @Published var watermarkOpacity: CGFloat = 0.6
    @Published var watermarkColor: Color = .white

    @Published var watermarkText: String = ScreenshotPreferences.defaultWatermarkText

    /// Every capture starts from Settings › Screenshot rather than from
    /// whatever the previous screenshot left behind.
    func prepareForCapture() {
        watermarkEnabled = ScreenshotPreferences.watermarkOnByDefault
        let stored = ScreenshotPreferences.watermarkText
        watermarkText = stored.isEmpty ? ScreenshotPreferences.defaultWatermarkText : stored
        watermarkHidden = false
    }

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
    var onRedo: () -> Void = {}
    var onScroll: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onPin: () -> Void = {}
    var onClose: () -> Void = {}

    /// The toolbar offers the scroll entry only when the feature is shipping.
    var showsScrollingCapture: Bool { ScreenshotAvailability.scrollingCapture }

    // MARK: - Selection style

    var selectedAnnotation: Annotation? {
        guard let index = selectionIndex,
              annotations.indices.contains(index) else { return nil }
        return annotations[index]
    }

    var hasSelectedAnnotation: Bool { selectedAnnotation != nil }

    /// The tool whose options describe what is being edited: the selected
    /// annotation's shape in Select, otherwise the active drawing tool.
    var displayTool: Tool {
        guard let shape = selectedAnnotation?.shape else { return tool }
        return Self.tool(for: shape)
    }

    var showsOptions: Bool {
        tool.hasOptions || hasSelectedAnnotation
    }

    /// Style writes target the selected annotation and always become the
    /// default for the next mark. Only a real change to a selected annotation
    /// is recorded in history; editing defaults alone is not a content change.
    var activeStyle: AnnotationStyle {
        get { selectedAnnotation?.style ?? defaultStyle }
        set {
            let previous = activeStyle
            if let index = selectionIndex,
               annotations.indices.contains(index),
               newValue != previous {
                recordUndoSnapshot()
                var annotation = annotations[index]
                annotation.style = newValue
                annotations[index] = annotation
            }
            defaultStyle = newValue
        }
    }

    func styleBinding<Value>(
        _ keyPath: WritableKeyPath<AnnotationStyle, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.activeStyle[keyPath: keyPath] },
            set: { self.activeStyle[keyPath: keyPath] = $0 }
        )
    }

    static func tool(for shape: Annotation.Shape) -> Tool {
        switch shape {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .text: return .text
        case .number: return .number
        case .mosaic: return .mosaic
        case .blur: return .blur
        }
    }

    // MARK: - History

    private struct HistoryState: Equatable {
        var annotations: [Annotation]
        var defaultStyle: AnnotationStyle
    }

    private static let historyLimit = 50

    /// Published so the toolbar's undo and redo buttons follow the stacks.
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [HistoryState] = []
    private var redoStack: [HistoryState] = []
    private var pendingSnapshot: HistoryState?
    private var isCoalescing = false

    private var currentSnapshot: HistoryState {
        HistoryState(annotations: annotations, defaultStyle: defaultStyle)
    }

    /// Records the state before a discrete content change, such as adding an
    /// annotation, deleting one, or editing the selected annotation's style.
    func recordUndoSnapshot() {
        guard !isCoalescing else { return }
        pushUndo(currentSnapshot)
    }

    /// Starts a drag or slider gesture. The snapshot is only pushed by
    /// `endInteractiveChange()` when the content actually changed, so a click
    /// that moves nothing creates no history and keeps the redo stack.
    func beginInteractiveChange() {
        guard !isCoalescing else { return }
        isCoalescing = true
        pendingSnapshot = currentSnapshot
    }

    func endInteractiveChange() {
        resolveInteractiveChange()
    }

    func undo() {
        guard canUndo else { return }
        resolveInteractiveChange()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(previous)
    }

    func redo() {
        guard canRedo else { return }
        resolveInteractiveChange()
        guard let next = redoStack.popLast() else { return }
        pushUndoWithoutClearingRedo(currentSnapshot)
        restore(next)
    }

    /// Starts a fresh capture with no leftover history.
    func resetHistory() {
        cancelInteractiveChange()
        undoStack.removeAll()
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    private func pushUndo(_ snapshot: HistoryState) {
        pushUndoWithoutClearingRedo(snapshot)
        redoStack.removeAll()
        refreshHistoryAvailability()
    }

    private func pushUndoWithoutClearingRedo(_ snapshot: HistoryState) {
        undoStack.append(snapshot)
        if undoStack.count > Self.historyLimit {
            undoStack.removeFirst(undoStack.count - Self.historyLimit)
        }
    }

    private func restore(_ snapshot: HistoryState) {
        annotations = snapshot.annotations
        defaultStyle = snapshot.defaultStyle
        selectionIndex = nil
        refreshHistoryAvailability()
    }

    /// Commits an in-progress gesture before history navigation. A gesture that
    /// really changed the content becomes one undo step; an unchanged one is
    /// dropped, leaving the redo stack alone.
    @discardableResult
    private func resolveInteractiveChange() -> Bool {
        guard isCoalescing else { return false }
        isCoalescing = false
        guard let snapshot = pendingSnapshot else { return false }
        pendingSnapshot = nil
        guard snapshot.annotations != annotations else {
            refreshHistoryAvailability()
            return false
        }
        pushUndo(snapshot)
        return true
    }

    private func cancelInteractiveChange() {
        isCoalescing = false
        pendingSnapshot = nil
    }

    /// A gesture in progress counts as undoable as soon as it changes content,
    /// and temporarily hides redo so the toolbar and the keyboard agree.
    private var pendingContentChanged: Bool {
        guard let pendingSnapshot else { return false }
        return pendingSnapshot.annotations != annotations
    }

    private func refreshHistoryAvailability() {
        let pendingChanged = pendingContentChanged
        canUndo = !undoStack.isEmpty || pendingChanged
        canRedo = !redoStack.isEmpty && !pendingChanged
    }
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
            if session.showsOptions {
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

            if session.showsScrollingCapture {
                Menu {
                    Button("Vertical scrolling capture") {
                        session.scrollingDirection = .vertical
                        session.onScroll()
                    }
                    Button("Horizontal scrolling capture") {
                        session.scrollingDirection = .horizontal
                        session.onScroll()
                    }
                } label: {
                    Image(systemName: "scroll").font(.system(size: 12.5, weight: .medium)).frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Scrolling capture: vertical or horizontal")
                .accessibilityLabel("Scrolling capture direction")
            }
            icon("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: session.canUndo, action: session.onUndo)
            icon("arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: session.canRedo, action: session.onRedo)
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
            if session.displayTool != .mosaic && session.displayTool != .blur {
                Button { showColors.toggle() } label: {
                    Circle().fill(session.activeStyle.color).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Color")
                .accessibilityLabel("Annotation color")
                .popover(isPresented: $showColors, arrowEdge: .bottom) {
                    HStack(spacing: 9) {
                        ForEach(Annotation.palette, id: \.self) { color in
                            Button { session.activeStyle.color = color; showColors = false } label: {
                                Circle().fill(color).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(session.activeStyle.color == color ? 0.7 : 0.15), lineWidth: 2))
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
        .padding(.leading, min(CGFloat(CaptureSession.Tool.allCases.firstIndex(of: session.displayTool) ?? 0) * 31, 150))
    }

    @ViewBuilder private var toolOptions: some View {
        let tool = session.displayTool
        switch tool {
        case .arrow:
            ForEach([ArrowStyle.straight, .curved, .elbow, .sCurve], id: \.self) { style in
                optionButton(style.title, selected: session.activeStyle.arrowStyle == style) { session.activeStyle.arrowStyle = style } label: {
                    ArrowOptionIcon(style: style).stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 24, height: 20)
                }
            }
            patternControls
            lineWidthSlider
        case .rectangle, .ellipse:
            ForEach(ShapeFillStyle.allCases, id: \.self) { style in
                optionButton(String(describing: style).capitalized, selected: session.activeStyle.fillStyle == style) { session.activeStyle.fillStyle = style } label: {
                    FillOptionIcon(style: style, ellipse: tool == .ellipse).frame(width: 20, height: 20)
                }
            }
            patternControls
            lineWidthSlider
        case .text:
            ForEach([CGFloat(0.016), 0.022, 0.030], id: \.self) { size in
                optionButton("Text size \(Int(size * 1000))", selected: session.activeStyle.textScale == size) { session.activeStyle.textScale = size } label: {
                    Text("A").font(.system(size: size * 600 + 4, weight: .medium))
                }
            }
            Divider().frame(height: 18)
            optionIcon("text.bubble", "Bubble background", selected: session.activeStyle.textBubble) { session.activeStyle.textBubble.toggle() }
        case .number:
            optionIcon("1.circle", "Circle marker", selected: session.activeStyle.numberStyle == .circle) { session.activeStyle.numberStyle = .circle }
            optionIcon("1.square", "Square marker", selected: session.activeStyle.numberStyle == .square) { session.activeStyle.numberStyle = .square }
        case .mosaic, .blur:
            Image(systemName: tool.symbol).frame(width: 26)
            optionSlider("Strength", value: session.styleBinding(\.mosaicBlock), range: 6...32)
        case .highlighter:
            lineWidthSlider
            Image(systemName: "circle.lefthalf.filled").frame(width: 22)
            optionSlider("Opacity", value: session.styleBinding(\.highlighterAlpha), range: 0.15...0.7)
        case .line, .pen:
            patternControls
            lineWidthSlider
        case .select:
            EmptyView()
        }
    }

    private var lineWidthSlider: some View {
        HStack(spacing: 3) {
            Divider().frame(height: 18)
            Image(systemName: "lineweight").frame(width: 23)
            optionSlider("Line width", value: session.styleBinding(\.lineWidth), range: 0.0015...0.016)
        }
    }

    private var patternControls: some View {
        HStack(spacing: 3) {
            Divider().frame(height: 18)
            ForEach(LinePattern.allCases, id: \.self) { pattern in
                optionButton(String(describing: pattern).capitalized + " line", selected: session.activeStyle.linePattern == pattern) { session.activeStyle.linePattern = pattern } label: {
                    LinePatternIcon(pattern: pattern).frame(width: 22, height: 18)
                }
            }
        }
    }

    private func optionSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        Slider(value: value, in: range, onEditingChanged: { editing in
            if editing {
                session.beginInteractiveChange()
            } else {
                session.endInteractiveChange()
            }
        })
        .controlSize(.mini).frame(width: 90)
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
        switch session.defaultStyle.arrowStyle {
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

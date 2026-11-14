import ServiceManagement
import SwiftUI
import SwitchKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionCenter

    @State private var pane: Pane?

    init(model: AppModel, permissions: PermissionCenter, initialPane: Pane = .general) {
        self.model = model
        self.permissions = permissions
        _pane = State(initialValue: initialPane)
    }

    enum Pane: String, CaseIterable, Identifiable {
        case general, customize, screenshot, textRecognition, recording, shortcuts, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return t("General")
            case .customize: return t("Customize")
            case .screenshot: return t("Screenshot")
            case .textRecognition: return t("Recognize Text")
            case .recording: return t("Recording")
            case .shortcuts: return t("Shortcuts")
            case .about: return t("About")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .customize: return "slider.horizontal.3"
            case .screenshot: return "camera.viewfinder"
            case .textRecognition: return "text.viewfinder"
            case .recording: return "record.circle"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $pane) {
                ForEach(Pane.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 186)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .general {
        case .general: GeneralPane(permissions: permissions)
        case .customize: CustomizePane(model: model)
        case .screenshot: ScreenshotPane(model: model)
        case .textRecognition: TextRecognitionPane(model: model)
        case .recording: RecordingPane()
        case .shortcuts: ShortcutsPane(model: model)
        case .about: AboutPane()
        }
    }
}

// MARK: - Shared chrome

private struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }
}

/// Small rounded tile that gives each row an anchor without shouting.
private struct SymbolTile: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var permissions: PermissionCenter
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var language = AppLanguage.current
    @State private var languageChanged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(
                    title: t("General"),
                    subtitle: t("Permissions, startup, and the places macOS keeps them.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Permissions"))

                    VStack(spacing: 0) {
                        PermissionStatusRow(
                            title: t("Accessibility"),
                            detail: t("Lock Keyboard and Screen Clean."),
                            granted: permissions.accessibility,
                            grantTitle: t("Grant"),
                            onGrant: { permissions.requestAccessibility() },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Accessibility") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: t("Screen Recording"),
                            detail: t("Screenshot. macOS applies the grant after a relaunch."),
                            granted: permissions.screenRecording,
                            grantTitle: t("Grant"),
                            onGrant: { permissions.requestScreenRecording() },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_ScreenCapture") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: t("Automation — System Events"),
                            detail: t("Dark Mode."),
                            granted: permissions.systemEvents == .granted,
                            grantTitle: permissions.systemEvents == .unknown ? t("Check") : t("Grant"),
                            onGrant: { permissions.requestAutomation(bundleID: "com.apple.systemevents") },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: t("Automation — Finder"),
                            detail: t("Empty Trash and its item count."),
                            granted: permissions.finder == .granted,
                            grantTitle: permissions.finder == .unknown ? t("Check") : t("Grant"),
                            onGrant: { permissions.requestAutomation(bundleID: "com.apple.finder") },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: t("Microphone"),
                            detail: t("Recording."),
                            granted: permissions.microphone == .authorized,
                            grantTitle: t("Allow"),
                            onGrant: { permissions.requestMicrophone() },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Microphone") }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    }

                    if let message = permissions.automationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(permissions.automationMessageIsError ? Color.orange : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Startup"))

                    HStack(alignment: .center, spacing: 12) {
                        SymbolTile(symbol: "power")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Launch at login"))
                            Text(t("Needs SwitchDeck in /Applications."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, enabled in
                                do {
                                    if enabled {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                    loginError = nil
                                } catch {
                                    loginError = error.localizedDescription
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                    }

                    if let loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Language"))

                    HStack(alignment: .center, spacing: 12) {
                        SymbolTile(symbol: "globe")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Interface language"))
                            Text(t("Follows the system until you pick one; a change applies after a relaunch."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Picker("", selection: $language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)
                        .onChange(of: language) { _, picked in
                            picked.apply()
                            languageChanged = true
                        }
                    }

                    if languageChanged {
                        HStack {
                            Spacer()
                            Button(t("Relaunch SwitchDeck")) { AppLanguage.relaunch() }
                        }
                    }
                }
            }
            .padding(28)
        }
        .onAppear { permissions.startMonitoring() }
        .onDisappear { permissions.stopMonitoring() }
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 30)
    }
}

// MARK: - Customize

private struct CustomizePane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(
                title: t("Customize"),
                subtitle: t("Drag to reorder. Turn a switch off to hide it from the menu.")
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)

            List {
                ForEach(model.orderedItems, id: \.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help(t("Drag to reorder"))

                        SymbolTile(symbol: item.symbolName)

                        Text(item.title)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { model.config.isEnabled(item.id) },
                            set: { model.setEnabled(item.id, $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(t("Move Up")) { model.move(item.id, by: -1) }
                        Button(t("Move Down")) { model.move(item.id, by: 1) }
                        Divider()
                        Button(model.config.isEnabled(item.id) ? "Hide from Menu" : "Show in Menu") {
                            model.setEnabled(item.id, !model.config.isEnabled(item.id))
                        }
                    }
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Screenshot

/// The tinted row container the panes share.
private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct ScreenshotPane: View {
    @ObservedObject var model: AppModel

    @AppStorage(ScreenshotPreferences.prefixKey) private var prefix = "SwitchDeck"
    @AppStorage(ScreenshotPreferences.formatKey) private var format = "png"
    @AppStorage(ScreenshotPreferences.qualityKey) private var quality = 0.9
    @AppStorage(ScreenshotPreferences.delayKey) private var delay = 0
    @AppStorage(ScreenshotPreferences.colorFormatKey) private var colorFormat = 0
    @AppStorage(ScreenshotPreferences.watermarkDefaultKey) private var watermarkDefault = false
    @AppStorage(ScreenshotPreferences.watermarkTextKey) private var watermarkText = ""

    @State private var folderPath = ScreenshotPreferences.folder.path

    private var selectedFormat: ScreenshotPreferences.ImageFormat {
        ScreenshotPreferences.ImageFormat(rawValue: format) ?? .png
    }

    private var isCustomFolder: Bool {
        folderPath != ScreenshotPreferences.downloads.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(
                    title: t("Screenshot"),
                    subtitle: t("The capture shortcut, how it behaves, and what happens to saved images.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Shortcut"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "camera.viewfinder")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Capture"))
                                Text(t("Starts a region, window or full-screen capture from any app."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShortcutField(model: model, id: ScreenshotCoordinator.id)
                        }
                        .padding(.vertical, 6)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Capture"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "timer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Delay"))
                                Text(t("Counts down before the overlay appears, so a menu or hover state can be caught."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $delay) {
                                Text(t("Off")).tag(0)
                                Text(t("3 s")).tag(3)
                                Text(t("5 s")).tag(5)
                                Text(t("10 s")).tag(10)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "eyedropper")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Colour readout"))
                                Text(t("Format shown under the pointer; ⌥ still cycles while capturing."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $colorFormat) {
                                ForEach(ScreenshotPreferences.ColorFormat.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        .padding(.vertical, 6)
                    }

                    if delay > 0 {
                        Text(t("The frame is taken when the countdown ends; a second press of the shortcut cancels it."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Saving"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "folder")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Save to"))
                                Text(abbreviated(folderPath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(folderPath)
                            }
                            Spacer()
                            Button(t("Choose…")) { chooseFolder() }
                                .controlSize(.small)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folderPath)])
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderless)
                            .help(t("Show in Finder"))
                            if isCustomFolder {
                                Button(t("Downloads")) { useDownloads() }
                                    .controlSize(.small)
                                    .help(t("Save to ~/Downloads again"))
                            }
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                SymbolTile(symbol: "textformat")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("File name prefix"))
                                    Text(t("Goes before “Screenshot_<date>_<time>”. Empty drops it."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField(t("SwitchDeck"), text: $prefix)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 168)
                            }

                            Text(tf("Saves as %@", ScreenshotPreferences.fileName(prefix: prefix, format: selectedFormat)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 36)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "photo")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Format"))
                                Text(selectedFormat.isLossy
                                     ? "Smaller files; the signature text only stays in PNG metadata."
                                     : "Lossless, and keeps the signature text in the file's metadata.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $format) {
                                ForEach(ScreenshotPreferences.ImageFormat.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        .padding(.vertical, 6)

                        if selectedFormat.isLossy {
                            RowDivider()

                            HStack(spacing: 12) {
                                SymbolTile(symbol: "dial.medium")
                                Text(t("Quality"))
                                Spacer()
                                Slider(value: $quality, in: 0.5...1.0)
                                    .frame(width: 168)
                                Text(tf("%d%%", Int((quality * 100).rounded())))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Watermark"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "signature")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Add a signature by default"))
                                Text(t("Each capture still has its own toggle in the editor."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $watermarkDefault)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "character.cursor.ibeam")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Text"))
                                Text(t("Empty uses the macOS full user name."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField(ScreenshotPreferences.defaultWatermarkText, text: $watermarkText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        .padding(.vertical, 6)
                    }

                    Text(t("In the editor: Return copies, Space saves, P pins, Esc cancels."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folderPath)
        panel.prompt = "Choose"
        panel.message = "Where saved screenshots go"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: ScreenshotPreferences.folderKey)
        folderPath = url.path
    }

    private func useDownloads() {
        UserDefaults.standard.removeObject(forKey: ScreenshotPreferences.folderKey)
        folderPath = ScreenshotPreferences.downloads.path
    }
}

// MARK: - Recording

private struct RecordingPane: View {
    @AppStorage(RecordingSwitch.folderDefaultsKey) private var folder = ""
    @AppStorage(RecordingSwitch.inputDeviceDefaultsKey) private var inputUID = ""

    @State private var devices: [AudioInput.Device] = []

    private var folderPath: String {
        folder.isEmpty ? RecordingSwitch.defaultFolder.path : folder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(
                    title: t("Recording"),
                    subtitle: t("Where audio goes, and which microphone it hears.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Storage"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "folder")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Save to"))
                                Text(abbreviated(folderPath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(folderPath)
                            }
                            Spacer()
                            Button(t("Choose…")) { chooseFolder() }
                                .controlSize(.small)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folderPath)])
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderless)
                            .help(t("Show in Finder"))
                            if !folder.isEmpty {
                                Button(t("Music")) { folder = "" }
                                    .controlSize(.small)
                                    .help(t("Use ~/Music/SwitchDeck again"))
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Text(t("Recordings are AAC in an .m4a file, named “Recording <date>.m4a”."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Input"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "mic")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Microphone"))
                                Text(t("Used from the next recording on. A missing device falls back to the system default."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $inputUID) {
                                Text(t("System default")).tag("")
                                ForEach(devices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        .padding(.vertical, 6)
                    }

                    Text(t("AVAudioRecorder only records from the macOS default input, so SwitchDeck switches that default while a recording runs and puts the previous one back when it stops."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
        .onAppear {
            devices = AudioInput.devices()
            if !inputUID.isEmpty, !devices.contains(where: { $0.id == inputUID }) {
                inputUID = ""
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folderPath)
        panel.prompt = "Choose"
        panel.message = "Where recordings go"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
    }
}

// MARK: - Recognize Text

private struct TextRecognitionPane: View {
    @ObservedObject var model: AppModel

    @AppStorage(ScreenshotPreferences.silentRecognitionKey) private var silentRecognition = false
    @AppStorage(ScreenshotPreferences.autoCopyRecognitionKey) private var autoCopyRecognition = false
    @AppStorage(ScreenshotPreferences.qrLinkActionKey) private var qrLinkAction = ScreenshotPreferences.QRLinkAction.copy.rawValue
    @AppStorage(ScreenshotPreferences.toastSecondsKey) private var toastSeconds = ScreenshotPreferences.defaultToastSeconds

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(
                    title: t("Recognize Text"),
                    subtitle: t("Select a region or window and read its text or QR code, on this Mac.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Shortcut"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "text.viewfinder")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Recognize Text"))
                                Text(t("Starts a selection from any app; choosing the area runs recognition."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShortcutField(model: model, id: ScreenshotCoordinator.recognizeTextID)
                        }
                        .padding(.vertical, 6)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: t("Result"))

                    SettingsCard {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "doc.on.clipboard")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Silent recognition"))
                                Text(t("Copy the result and show a short preview instead of opening the result window."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $silentRecognition)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "doc.on.doc")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Auto copy"))
                                Text(t("Also copy the text when the result window opens. Silent recognition always copies."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $autoCopyRecognition)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(silentRecognition)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "qrcode")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("QR link action"))
                                Text(t("When a QR code holds a web link: copy it, or open it in the browser as well."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $qrLinkAction) {
                                Text(t("Copy")).tag(ScreenshotPreferences.QRLinkAction.copy.rawValue)
                                Text(t("Open")).tag(ScreenshotPreferences.QRLinkAction.open.rawValue)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "bell")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Notification duration"))
                                Text(t("How long the notice after a silent recognition or an opened link stays on screen."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $toastSeconds) {
                                ForEach(ScreenshotPreferences.toastSecondsChoices, id: \.self) { seconds in
                                    Text(tf("%d s", seconds)).tag(seconds)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                        .padding(.vertical, 6)

                        RowDivider()

                        HStack(spacing: 12) {
                            SymbolTile(symbol: "lock.shield")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("On this Mac"))
                                Text(t("Uses the macOS Vision models; nothing is uploaded. Reads Chinese, English, Japanese and Korean, and copies a QR code's content when one is found."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shortcuts

/// Record / change / clear one shortcut. Shared by Shortcuts and Screenshot so
/// both panes behave the same way.
private struct ShortcutField: View {
    @ObservedObject var model: AppModel
    let id: String

    @State private var recording = false
    @State private var hint: String?
    @State private var monitor = KeyCaptureMonitor()

    var body: some View {
        HStack(spacing: 8) {
            if recording {
                Text(hint ?? "Press shortcut…")
                    .font(.callout)
                    .foregroundStyle(hint == nil ? Color.secondary : Color.orange)
                ProgressView()
                    .controlSize(.small)
                Button(t("Cancel"), action: stop)
                    .buttonStyle(.borderless)
                    .font(.callout)
            } else if let binding = model.config.hotkey(for: id) {
                Text(binding.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button(t("Change"), action: start)
                    .buttonStyle(.borderless)
                    .font(.callout)
                Button {
                    model.setHotkey(nil, for: id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.borderless)
                .help(t("Clear shortcut"))
            } else {
                Button(t("Record"), action: start)
                    .controlSize(.small)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        hint = nil
        recording = true

        monitor.start { event in
            if event.keyCode == 53 {
                stop()
                return true
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                model.setHotkey(nil, for: id)
                stop()
                return true
            }

            guard let binding = HotkeyRecorder.binding(from: event) else {
                hint = "Add ⌘, ⌥ or ⌃."
                return true
            }

            model.setHotkey(binding, for: id)
            stop()
            return true
        }
    }

    private func stop() {
        monitor.stop()
        recording = false
        hint = nil
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(
                title: t("Shortcuts"),
                subtitle: t("Record a shortcut to toggle a switch from any app. Esc cancels, Delete clears.")
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)

            List {
                ForEach(model.orderedItems.filter { $0.id != ScreenshotCoordinator.id && $0.id != ScreenshotCoordinator.recognizeTextID }, id: \.id) { item in
                    HStack(spacing: 10) {
                        SymbolTile(symbol: item.symbolName)
                        Text(item.title)

                        Spacer()

                        ShortcutField(model: model, id: item.id)
                    }
                    .padding(.vertical, 4)
                    .opacity(model.config.isEnabled(item.id) ? 1 : 0.45)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)

            Text(t("Screenshot’s shortcut lives in Settings › Screenshot, next to where its images go."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)

            ForEach(model.hotkeyIssues, id: \.self) { issue in
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 28)
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            Text(t("SwitchDeck"))
                .font(.system(size: 22, weight: .semibold))

            Text(tf("Version %@", Self.version))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(t("Menu-bar switches for macOS.\nNo telemetry, no in-app purchase."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 18) {
                Link(t("Repository"), destination: URL(string: "https://github.com/jwcrystal/switchdeck")!)
                Link(t("Report an Issue"), destination: URL(string: "https://github.com/jwcrystal/switchdeck/issues")!)
            }
            .font(.callout)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

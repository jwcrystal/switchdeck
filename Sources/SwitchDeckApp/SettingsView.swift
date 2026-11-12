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
        case general, customize, shortcuts, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .customize: return "Customize"
            case .shortcuts: return "Shortcuts"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .customize: return "slider.horizontal.3"
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PaneHeader(
                    title: "General",
                    subtitle: "Permissions, startup, and the places macOS keeps them."
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Permissions")

                    VStack(spacing: 0) {
                        PermissionStatusRow(
                            title: "Accessibility",
                            detail: "Lock Keyboard and Screen Clean.",
                            granted: permissions.accessibility,
                            grantTitle: "Grant",
                            onGrant: { permissions.requestAccessibility() },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Accessibility") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: "Automation — System Events",
                            detail: "Dark Mode.",
                            granted: permissions.systemEvents == .granted,
                            grantTitle: permissions.systemEvents == .unknown ? "Check" : "Grant",
                            onGrant: { permissions.requestAutomation(bundleID: "com.apple.systemevents") },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: "Automation — Finder",
                            detail: "Empty Trash and its item count.",
                            granted: permissions.finder == .granted,
                            grantTitle: permissions.finder == .unknown ? "Check" : "Grant",
                            onGrant: { permissions.requestAutomation(bundleID: "com.apple.finder") },
                            onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                        )

                        RowDivider()

                        PermissionStatusRow(
                            title: "Microphone",
                            detail: "Recording.",
                            granted: permissions.microphone == .authorized,
                            grantTitle: "Allow",
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
                    SectionTitle(text: "Startup")

                    HStack(alignment: .center, spacing: 12) {
                        SymbolTile(symbol: "power")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login")
                            Text("Needs SwitchDeck in /Applications.")
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
                title: "Customize",
                subtitle: "Drag to reorder. Turn a switch off to hide it from the menu."
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)

            List {
                ForEach(model.orderedItems, id: \.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .help("Drag to reorder")

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
                        Button("Move Up") { model.move(item.id, by: -1) }
                        Button("Move Down") { model.move(item.id, by: 1) }
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

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var model: AppModel

    @State private var recordingID: String?
    @State private var recorderMessage: String?
    @State private var monitor = KeyCaptureMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(
                title: "Shortcuts",
                subtitle: "Record a shortcut to toggle a switch from any app. Esc cancels, Delete clears."
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)

            List {
                ForEach(model.orderedItems, id: \.id) { item in
                    row(for: item)
                        .opacity(model.config.isEnabled(item.id) ? 1 : 0.45)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 28)
            }

            ForEach(model.hotkeyIssues, id: \.self) { issue in
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 28)
            }
        }
        .padding(.bottom, 20)
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private func row(for item: SwitchItem) -> some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: item.symbolName)
            Text(item.title)

            Spacer()

            if recordingID == item.id {
                Text("Press shortcut…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            } else if let binding = model.config.hotkey(for: item.id) {
                Text(binding.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button("Change") { startRecording(item.id) }
                    .buttonStyle(.borderless)
                    .font(.callout)
                Button {
                    model.setHotkey(nil, for: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
            } else {
                Button("Record") { startRecording(item.id) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func startRecording(_ id: String) {
        recorderMessage = nil
        recordingID = id

        monitor.start { event in
            if event.keyCode == 53 {
                stopRecording()
                return true
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                model.setHotkey(nil, for: id)
                stopRecording()
                return true
            }

            guard let binding = HotkeyRecorder.binding(from: event) else {
                recorderMessage = "Add ⌘, ⌥ or ⌃ to the shortcut."
                return true
            }

            model.setHotkey(binding, for: id)
            stopRecording()
            return true
        }
    }

    private func stopRecording() {
        monitor.stop()
        recordingID = nil
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            Text("SwitchDeck")
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(Self.version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A local reimplementation of AnySwitch's menu-bar switches.\nNo telemetry, no in-app purchase.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 18) {
                Link("Repository", destination: URL(string: "https://github.com/jared/switchdeck")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/jared/switchdeck/issues")!)
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

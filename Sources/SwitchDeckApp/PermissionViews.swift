import AppKit
import SwiftUI

/// One permission with its live state and the two ways out: ask again, or open
/// the matching System Settings pane.
struct PermissionStatusRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grantTitle: String
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if granted {
                Label("Granted", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(grantTitle, action: onGrant)
                    .controlSize(.small)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .help("Open the matching System Settings pane")
            }
        }
        .padding(.vertical, 6)
    }
}

/// Shown once at launch while something is missing. This is the only place the
/// app triggers a system permission dialog.
struct SetupView: View {
    @ObservedObject var permissions: PermissionCenter
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up SwitchDeck")
                        .font(.title2.weight(.semibold))
                    Text("macOS only asks here. The menu never prompts while you use a switch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                PermissionStatusRow(
                    title: "Accessibility",
                    detail: "Lock Keyboard and Screen Clean.",
                    granted: permissions.accessibility,
                    grantTitle: "Grant",
                    onGrant: { permissions.requestAccessibility() },
                    onOpenSettings: { permissions.openPrivacyPane("Privacy_Accessibility") }
                )

                Divider()

                PermissionStatusRow(
                    title: "Automation — System Events",
                    detail: "Dark Mode.",
                    granted: permissions.systemEvents == .granted,
                    grantTitle: permissions.systemEvents == .unknown ? "Check" : "Grant",
                    onGrant: { permissions.requestAutomation(bundleID: "com.apple.systemevents") },
                    onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                )

                Divider()

                PermissionStatusRow(
                    title: "Automation — Finder",
                    detail: "Empty Trash and its item count.",
                    granted: permissions.finder == .granted,
                    grantTitle: permissions.finder == .unknown ? "Check" : "Grant",
                    onGrant: { permissions.requestAutomation(bundleID: "com.apple.finder") },
                    onOpenSettings: { permissions.openPrivacyPane("Privacy_Automation") }
                )

                Divider()

                PermissionStatusRow(
                    title: "Microphone",
                    detail: "Recording.",
                    granted: permissions.microphone == .authorized,
                    grantTitle: "Allow",
                    onGrant: { permissions.requestMicrophone() },
                    onOpenSettings: { permissions.openPrivacyPane("Privacy_Microphone") }
                )
            }

            Text("Grants survive rebuilds: the app is signed with a local identity, so macOS keeps recognising it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let message = permissions.automationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(permissions.automationMessageIsError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Not Now") { onClose() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            permissions.startMonitoring()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                permissions.verifyAutomationAtLaunch()
            }
        }
        .onDisappear { permissions.stopMonitoring() }
    }
}

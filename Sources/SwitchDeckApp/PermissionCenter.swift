import AppKit
import AVFoundation
import CoreServices
import SwitchKit

/// Reads and requests the three permissions SwitchDeck can need.
///
/// The app asks once, in the setup window shown at launch. Switches never call a
/// prompting API themselves, so using the menu cannot trigger another dialog.
@MainActor
final class PermissionCenter: ObservableObject {
    enum AutomationState: Equatable {
        case granted
        case denied
        case unknown
    }

    @Published private(set) var accessibility = false
    @Published private(set) var microphone: AVAuthorizationStatus = .notDetermined
    @Published private(set) var screenRecording = false
    @Published private(set) var systemEvents: AutomationState = .unknown
    @Published private(set) var finder: AutomationState = .unknown
    /// Result of the last "Grant" attempt, shown under the rows.
    @Published private(set) var automationMessage: String?
    @Published private(set) var automationMessageIsError = false

    private var refreshTimer: Timer?

    var allGranted: Bool {
        accessibility && microphone == .authorized && systemEvents == .granted
    }

    var missingCount: Int {
        var count = 0
        if !accessibility { count += 1 }
        if microphone != .authorized { count += 1 }
        if systemEvents != .granted { count += 1 }
        return count
    }

    /// Live status while a settings or setup window is open, so a toggle in
    /// System Settings shows up without relaunching.
    func startMonitoring() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        screenRecording = CGPreflightScreenCaptureAccess()

        // Unknown usually means the target app is not running, not that the
        // grant is missing; keep the last known answer instead of flapping.
        let systemEventsState = Self.automationState(bundleID: "com.apple.systemevents")
        if systemEventsState != .unknown { systemEvents = systemEventsState }

        let finderState = Self.automationState(bundleID: "com.apple.finder")
        if finderState != .unknown { finder = finderState }
    }

    /// First-launch check: send one harmless event per target. A grant that is
    /// already in place returns instantly; otherwise this is where macOS asks.
    func verifyAutomationAtLaunch() {
        for bundleID in ["com.apple.systemevents", "com.apple.finder"] where state(for: bundleID) != .granted {
            do {
                _ = try Automation.run(Self.probeScript(for: bundleID))
                setAutomationState(.granted, for: bundleID)
            } catch {
                setAutomationState(.denied, for: bundleID)
            }
        }
    }

    private func state(for bundleID: String) -> AutomationState {
        switch bundleID {
        case "com.apple.systemevents": return systemEvents
        case "com.apple.finder": return finder
        default: return .unknown
        }
    }

    // MARK: - Requests

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestAutomation(bundleID: String) {
        automationMessage = nil
        automationMessageIsError = false

        do {
            // Sending a harmless real event is what makes macOS show the
            // Automation prompt; asking the permission API alone can return
            // without any dialog.
            _ = try Automation.run(Self.probeScript(for: bundleID))
            refresh()
            // A successful send is the ground truth, even if the query API
            // lags behind right after a grant.
            setAutomationState(.granted, for: bundleID)
            automationMessage = "\(Self.displayName(for: bundleID)) is allowed."
        } catch {
            refresh()
            automationMessage = "\(Self.displayName(for: bundleID)): \(error.localizedDescription)"
            automationMessageIsError = true
        }
    }

    private func setAutomationState(_ state: AutomationState, for bundleID: String) {
        switch bundleID {
        case "com.apple.systemevents": systemEvents = state
        case "com.apple.finder": finder = state
        default: break
        }
    }

    private static func probeScript(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.systemevents":
            return #"tell application "System Events" to get name"#
        case "com.apple.finder":
            return #"tell application "Finder" to get name of startup disk"#
        default:
            return "tell application id \"\(bundleID)\" to get name"
        }
    }

    private static func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.systemevents": return "System Events"
        case "com.apple.finder": return "Finder"
        default: return bundleID
        }
    }

    func openPrivacyPane(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    private static func automationState(bundleID: String) -> AutomationState {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else {
            return .unknown
        }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false)
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            // procNotFound and friends: no answer, not a refusal.
            return .unknown
        }
    }
}

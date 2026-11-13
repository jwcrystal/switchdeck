import AppKit
import SwiftUI
import SwitchKit
import XCTest
@testable import SwitchDeckApp

final class WindowSelectionTests: XCTestCase {
    @MainActor
    func testClickSelectsOwnSettingsWindowForWindowCapture() async throws {
        try await assertSettingsWindowCanBeCaptured(floating: false)
    }

    @MainActor
    func testClickSelectsFloatingSettingsPanelForWindowCapture() async throws {
        try await assertSettingsWindowCanBeCaptured(floating: true)
    }

    @MainActor
    func testImmediateCopyWaitsForSettingsWindowImage() async throws {
        try await assertSettingsWindowCanBeCaptured(floating: false, copyImmediately: true)
    }

    @MainActor
    func testLiveSettingsPageCanBeSelectedCapturedAndDelivered() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWITCHDECK_LIVE_CAPTURE_TESTS"] == "1")
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "Screen Recording permission is required")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("window-capture-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let store = ConfigStore(url: configURL)
        store.update { $0.didSeedScreenshotShortcut = true }
        let model = AppModel(store: store)
        let hosting = NSHostingController(rootView: SettingsView(
            model: model, permissions: PermissionCenter(), initialPane: .screenshot
        ))
        let settings = NSWindow(contentViewController: hosting)
        settings.title = "SwitchDeck"
        settings.styleMask = [.titled, .closable, .miniaturizable]
        settings.isReleasedWhenClosed = false
        settings.setContentSize(NSSize(width: 720, height: 540))
        settings.animationBehavior = .none
        settings.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - settings.frame.width / 2,
                                       y: screen.visibleFrame.midY - settings.frame.height / 2))
        settings.orderFrontRegardless()
        settings.displayIfNeeded()
        defer { settings.close() }
        try await Task.sleep(nanoseconds: 100_000_000)

        let id = CGWindowID(settings.windowNumber)
        let captured = expectation(description: "The actual Settings page is selected, captured and delivered")
        let service = ScreenCaptureService()
        let controller = SelectionController()
        var result: CapturePayload?
        controller.begin(
            onCapture: { payload, _ in
                result = payload
                captured.fulfill()
            },
            onCancel: {},
            captureBase: { _, _ in nil },
            captureWindows: { targets, canvas, screen in
                XCTAssertEqual(targets.map(\.id), [id])
                do {
                    let image = try await service.captureWindow(windowID: id)
                    return WindowComposer.compose(shots: [(image, targets[0].rect)],
                                                  canvas: canvas, scale: screen.backingScaleFactor)
                } catch {
                    XCTFail("Settings capture failed: \(error)")
                    return nil
                }
            }
        )
        let view = try XCTUnwrap(NSApp.windows.compactMap { $0.contentView as? SelectionView }
            .first { $0.screen == screen })
        defer { if controller.isActive { view.onCancel?() } }
        // SwiftUI layout and WindowServer animations are asynchronous.
        try await waitForWindowToSettle(settings)
        let point = CGPoint(x: settings.frame.midX - screen.frame.minX,
                            y: settings.frame.midY - screen.frame.minY)
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: point))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: point))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: point))
        controller.session.onCopy()
        await fulfillment(of: [captured], timeout: 5)
        let payload = try XCTUnwrap(result)
        let image = try XCTUnwrap(payload.base)
        XCTAssertEqual(payload.rect, settings.frame.intersection(screen.frame),
                       "The selected Settings window must not gain blank margins")
        XCTAssertEqual(image.width, Int((payload.rect.width * screen.backingScaleFactor).rounded()))
        XCTAssertEqual(image.height, Int((payload.rect.height * screen.backingScaleFactor).rounded()))
        XCTAssertFalse(controller.isActive)

        if let directory = ProcessInfo.processInfo.environment["SWITCHDECK_CAPTURE_EVIDENCE_DIRECTORY"] {
            let rendered = AnnotationRenderer.render(base: image, annotations: payload.annotations)
            let cg = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try png.write(to: destination.appendingPathComponent("switchdeck_settings_window.png"))
        }
    }

    @MainActor
    func testFailedWindowCaptureDoesNotFallBackToDesktopOrDeliverWrongImage() async throws {
        try await assertSettingsWindowCanBeCaptured(floating: false, captureSucceeds: false)
    }

    /// Opt-in live pixel verification: requires a logged-in desktop and Screen
    /// Recording, neither of which is available on every CI runner.
    @MainActor
    func testLiveCaptureKeepsSettingsAndExcludesOnlyCaptureOverlay() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWITCHDECK_LIVE_CAPTURE_TESTS"] == "1")
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "Screen Recording permission is required")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let rect = CGRect(x: screen.visibleFrame.midX - 120, y: screen.visibleFrame.midY - 90,
                          width: 240, height: 180)
        let settings = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.title = "Window capture regression — Settings pixels"
        settings.backgroundColor = .green
        settings.orderFrontRegardless()
        settings.displayIfNeeded()
        defer { settings.close() }
        try await Task.sleep(nanoseconds: 50_000_000)

        let controller = SelectionController()
        controller.begin(onCapture: { _, _ in }, onCancel: {}, captureBase: { _, _ in nil },
                         captureWindows: { _, _, _ in nil })
        let view = try XCTUnwrap(NSApp.windows.compactMap { $0.contentView as? SelectionView }.first)
        defer { view.onCancel?() }
        // Make the overlay unmistakable if it accidentally leaks into pixels.
        view.window?.backgroundColor = .blue
        view.window?.isOpaque = true
        view.window?.displayIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)

        let displayID = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        let service = ScreenCaptureService()
        let windowImage = try await service.captureWindow(windowID: CGWindowID(settings.windowNumber))
        assertGreenCenter(windowImage, "A direct window capture must retain Settings even with the overlay on top")
        let region = try await service.captureRegion(displayID: displayID, rect: rect, screenFrame: screen.frame,
                                                     excludingWindowIDs: SelectionController.overlayWindowIDs)
        assertGreenCenter(region, "A region over Settings must exclude the overlay, not Settings itself")
        let display = try await service.captureDisplay(displayID: displayID,
                                                       excludingWindowIDs: SelectionController.overlayWindowIDs)
        let cropped = try XCTUnwrap(ScreenCaptureService.crop(image: display, to: rect, screenFrame: screen.frame))
        assertGreenCenter(cropped, "Full-display capture must also keep Settings")
    }

    private func assertGreenCenter(_ image: CGImage, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = bitmap.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.deviceRGB)
        XCTAssertGreaterThan(color?.greenComponent ?? 0, 0.85, message, file: file, line: line)
        // Allow display-profile conversion of the saturated AppKit green.
        XCTAssertGreaterThan((color?.greenComponent ?? 0) - (color?.redComponent ?? 1), 0.25,
                             message, file: file, line: line)
        XCTAssertGreaterThan((color?.greenComponent ?? 0) - (color?.blueComponent ?? 1), 0.25,
                             message, file: file, line: line)
    }

    /// Real WindowServer entries, not a mock picker: catches filters that drop
    /// this app's settings or nonzero-layer panels before the capture callback.
    @MainActor
    private func assertSettingsWindowCanBeCaptured(
        floating: Bool, copyImmediately: Bool = false, captureSucceeds: Bool = true
    ) async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let frame = CGRect(
            x: screen.visibleFrame.midX - 160,
            y: screen.visibleFrame.midY - 100,
            width: 320,
            height: 200
        )
        let settings: NSWindow
        if floating {
            let panel = NSPanel(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            settings = panel
        } else {
            settings = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        }
        settings.isReleasedWhenClosed = false
        settings.title = "Window capture regression — Settings"
        settings.orderFrontRegardless()
        settings.displayIfNeeded()
        defer { settings.close() }

        let id = CGWindowID(settings.windowNumber)
        var visible = false
        for _ in 0..<50 {
            let inventory = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            if inventory.contains(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == id }) {
                visible = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(visible, "The test settings window must be visible to WindowServer")
        guard visible else { return }

        let captured = expectation(description: "Click dispatches the settings window ID to window capture")
        let delivered = expectation(description: "The selected window image reaches the output")
        delivered.isInverted = !captureSucceeds
        var picked: [CGWindowID] = []
        var desktopRequests = 0
        let source = ScrollingCaptureTests.frame(offset: 0)
        let controller = SelectionController()
        var output: CapturePayload?
        controller.begin(
            onCapture: { payload, _ in
                output = payload
                delivered.fulfill()
            },
            onCancel: {},
            captureBase: { _, _ in
                desktopRequests += 1
                return source
            },
            captureWindows: { targets, _, _ in
                picked = targets.map(\.id)
                captured.fulfill()
                return captureSucceeds ? source : nil
            }
        )
        let view = try XCTUnwrap(NSApp.windows.compactMap { $0.contentView as? SelectionView }
            .first { $0.screen == screen })
        defer { if controller.isActive { view.onCancel?() } }
        let point = CGPoint(x: settings.frame.midX - screen.frame.minX,
                            y: settings.frame.midY - screen.frame.minY)
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: point))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: point))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: point))

        if copyImmediately {
            controller.session.onCopy()
            XCTAssertNil(output, "Output must wait for the selected window image instead of falling back to a desktop crop")
        }

        await fulfillment(of: [captured], timeout: 1)
        await Task.yield()
        XCTAssertEqual(picked, [id], "Settings must be picked as a window, not a desktop rectangle or a window behind it")
        if !copyImmediately { controller.session.onCopy() }
        await fulfillment(of: [delivered], timeout: captureSucceeds ? 1 : 0.1)
        XCTAssertEqual(desktopRequests, NSScreen.screens.count,
                       "Only the color sampler may request desktop pixels; a window capture must never silently become a desktop crop")
        if captureSucceeds {
            XCTAssertEqual(output?.base?.width, source.width)
            XCTAssertEqual(output?.base?.height, source.height)
            XCTAssertFalse(controller.isActive)
        } else {
            XCTAssertNil(output)
            XCTAssertTrue(controller.isActive, "Leave the failed selection visible so it can be cancelled explicitly")
        }
    }

    @MainActor
    private func waitForWindowToSettle(_ window: NSWindow) async throws {
        let primaryHeight = try XCTUnwrap(NSScreen.screens.first { $0.frame.origin == .zero }).frame.height
        var stableSamples = 0
        for _ in 0..<100 {
            let inventory = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let entry = inventory.first { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
            if let dictionary = entry?[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: dictionary) {
                let actual = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY,
                                    width: bounds.width, height: bounds.height)
                let expected = window.frame
                if abs(actual.minX - expected.minX) < 1, abs(actual.minY - expected.minY) < 1,
                   abs(actual.width - expected.width) < 1, abs(actual.height - expected.height) < 1 {
                    stableSamples += 1
                    if stableSamples >= 3 { return }
                } else {
                    stableSamples = 0
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The Settings window did not finish its layout/open animation")
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }
}

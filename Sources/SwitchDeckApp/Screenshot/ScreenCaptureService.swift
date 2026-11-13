import AppKit
import ScreenCaptureKit

/// Grabs pixels through ScreenCaptureKit (macOS 14+).
///
/// Region captures go through a full-display capture and a crop: the selection
/// overlay already knows the display and the rect, and cropping keeps the
/// coordinate maths in one place.
final class ScreenCaptureService {
    /// `SCShareableContent` costs a few hundred milliseconds; scrolling capture
    /// asks for a frame several times a second, so keep it briefly.
    private var cachedContent: (content: SCShareableContent, date: Date)?

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedContent, Date().timeIntervalSince(cachedContent.date) < 20 {
            return cachedContent.content
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = (content, Date())
        return content
    }

    enum CaptureError: LocalizedError {
        case permission
        case displayNotFound
        case windowNotFound
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .permission:
                return "SwitchDeck needs Screen Recording permission to take screenshots. Grant it in System Settings › Privacy & Security › Screen Recording, then relaunch."
            case .displayNotFound:
                return "The display could not be found for this capture."
            case .windowNotFound:
                return "The window went away before it could be captured."
            case .captureFailed(let message):
                return "Capture failed: \(message)"
            }
        }
    }

    func captureDisplay(displayID: CGDirectDisplayID, excludingOwnApp: Bool = false) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }

        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter: SCContentFilter
        if excludingOwnApp,
           let ownApp = content.applications.first(where: { $0.processID == getpid() }) {
            filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        // On this macOS, CGDisplayPixelsWide reports points; multiply by the
        // screen's scale so the capture is Retina-resolution.
        let pixels = Self.pixelSize(for: displayID)
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Captures just one region, so scrolling capture does not pay for a full
    /// Retina display on every frame.
    func captureRegion(
        displayID: CGDirectDisplayID,
        rect: CGRect,
        screenFrame: CGRect,
        excludingOwnApp: Bool = false
    ) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }

        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter: SCContentFilter
        if excludingOwnApp,
           let ownApp = content.applications.first(where: { $0.processID == getpid() }) {
            filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let pixels = Self.pixelSize(for: displayID)
        let scale = pixels.width / max(1, screenFrame.width)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        configuration.width = max(1, Int((rect.width * scale).rounded()))
        configuration.height = max(1, Int((rect.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    func captureWindow(windowID: CGWindowID) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }

        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    private static func pixelSize(for displayID: CGDirectDisplayID) -> CGSize {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            guard (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayID else { continue }
            let scale = screen.backingScaleFactor
            return CGSize(
                width: (screen.frame.width * scale).rounded(),
                height: (screen.frame.height * scale).rounded()
            )
        }
        return CGSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID))
    }

    /// Crops a full-display capture to a rect given in screen points.
    ///
    /// `rect` is in global screen coordinates (bottom-left origin); the image is
    /// top-left origin, so the vertical flip happens here.
    static func crop(image: CGImage, to rect: CGRect, screenFrame: CGRect) -> CGImage? {
        let scale = CGFloat(image.width) / screenFrame.width
        let localX = (rect.minX - screenFrame.minX) * scale
        let localY = (screenFrame.maxY - rect.maxY) * scale
        let crop = CGRect(
            x: localX.rounded(),
            y: localY.rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        return image.cropping(to: crop)
    }
}

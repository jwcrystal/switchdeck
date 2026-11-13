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

    static let cacheMaxAge: TimeInterval = 20

    /// A cached inventory can serve an exclusion list when it is fresh and
    /// already knows every window to exclude.
    static func canReuse(cachedWindowIDs: Set<CGWindowID>, age: TimeInterval, excluding: Set<CGWindowID>) -> Bool {
        age < cacheMaxAge && excluding.isSubset(of: cachedWindowIDs)
    }

    /// Reuses the cache while it is fresh and holds every excluded window.
    private func shareableContent(excluding: Set<CGWindowID>) async throws -> SCShareableContent {
        if excluding.isEmpty { return try await shareableContent() }
        if let cachedContent,
           Self.canReuse(
            cachedWindowIDs: Set(cachedContent.content.windows.map(\.windowID)),
            age: Date().timeIntervalSince(cachedContent.date),
            excluding: excluding
           ) {
            return cachedContent.content
        }
        return try await shareableContent(refresh: true)
    }

    private func shareableContent(refresh: Bool = false) async throws -> SCShareableContent {
        if !refresh, let cachedContent, Date().timeIntervalSince(cachedContent.date) < Self.cacheMaxAge {
            return cachedContent.content
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = (content, Date())
        return content
    }

    /// Looks a window up in the cache and refreshes once on a miss, so a window
    /// that appeared after the cache was filled can still be captured.
    private func window(id: CGWindowID) async throws -> SCWindow? {
        if let cachedContent,
           Date().timeIntervalSince(cachedContent.date) < 20,
           let window = cachedContent.content.windows.first(where: { $0.windowID == id }) {
            return window
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = (content, Date())
        return content.windows.first(where: { $0.windowID == id })
    }

    /// `SCWindow.frame` uses global top-left coordinates; `NSScreen` frames use
    /// the primary display's bottom-left origin.
    private static func scale(for windowFrame: CGRect) -> CGFloat {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            return NSScreen.main?.backingScaleFactor ?? 2
        }
        let center = CGPoint(x: windowFrame.midX, y: primary.frame.height - windowFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
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

    func captureDisplay(displayID: CGDirectDisplayID, excludingWindowIDs: Set<CGWindowID> = []) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }

        // Capture overlays are recreated each session. A cached inventory may
        // predate them, so refresh before resolving explicit window exclusions.
        let content = try await shareableContent(refresh: !excludingWindowIDs.isEmpty)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter {
            excludingWindowIDs.contains($0.windowID)
        })
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
        excludingWindowIDs: Set<CGWindowID> = []
    ) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }

        let content = try await shareableContent(excluding: excludingWindowIDs)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter {
            excludingWindowIDs.contains($0.windowID)
        })

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

        guard let window = try await window(id: windowID) else {
            throw CaptureError.windowNotFound
        }

        // One window can sit on a screen that is not the first in the list, and
        // a mixed-resolution setup would otherwise capture the wrong size.
        let scale = Self.scale(for: window.frame)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        // The composer draws the shadow, so keep the buffer at the window's own
        // size instead of letting ScreenCaptureKit shrink it to make room.
        configuration.ignoreShadowsSingleWindow = true

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

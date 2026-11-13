import Foundation

/// Availability of capture features that are implemented but not shipping.
///
/// Scrolling capture's engine stays compiled (and its unit tests keep
/// exercising stitching directly), but every user-facing route checks this
/// value: the toolbar entry, the session callback, the selection debug helper
/// and the coordinator's demo route. A build therefore cannot start scrolling
/// capture by accident, and tests may only assert that the routes are blocked.
enum ScreenshotAvailability {
    /// Vertical/horizontal scrolling capture is paused until its stitching
    /// problems are fixed. Do not turn this on to expose it to users yet.
    static let scrollingCapture = false
}

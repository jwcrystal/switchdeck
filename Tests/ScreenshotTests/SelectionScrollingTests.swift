import AppKit
import XCTest
@testable import SwitchDeckApp

final class SelectionScrollingTests: XCTestCase {
    private let region = CGRect(x: 20, y: 20, width: 200, height: 160)

    /// Builds an editing view whose frozen base image load is awaited, and
    /// returns the number of frame requests made so far.
    @MainActor
    private func editingView(
        session: CaptureSession,
        captureRequests: @escaping (Int) -> Void
    ) async -> SelectionView {
        _ = NSApplication.shared
        let screen = NSScreen.screens[0]
        let source = ScrollingCaptureTests.frame(offset: 0)
        var requests = 0
        let loaded = expectation(description: "Editor loads its frozen image")
        let view = SelectionView(screen: screen, session: session) { _, _ in
            requests += 1
            captureRequests(requests)
            if requests == 1 { loaded.fulfill() }
            return source
        }
        view.presetSelection(region)
        await fulfillment(of: [loaded], timeout: 1)
        await Task.yield()
        return view
    }

    @MainActor
    private func alphaAtCenter(of view: SelectionView) -> CGFloat {
        let bitmap = view.bitmapImageRepForCachingDisplay(in: region)!
        view.cacheDisplay(in: region, to: bitmap)
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.alphaComponent
    }

    @MainActor
    func testScrollingToolbarEntryIsHidden() {
        _ = NSApplication.shared
        XCTAssertFalse(ScreenshotAvailability.scrollingCapture)
        XCTAssertFalse(CaptureSession().showsScrollingCapture)
    }

    @MainActor
    func testOrdinaryEditingStillShowsItsCapturedBase() async {
        var requests: [Int] = []
        let view = await editingView(session: CaptureSession()) { requests.append($0) }
        XCTAssertEqual(requests, [1])
        XCTAssertGreaterThan(alphaAtCenter(of: view), 0.9, "Ordinary editing shows its captured base")
        XCTAssertFalse(view.isScrollingCaptureActive)
    }

    @MainActor
    func testVerticalScrollRequestCannotStartCapture() async {
        await assertScrollRequestBlocked(direction: .vertical)
    }

    @MainActor
    func testHorizontalScrollRequestCannotStartCapture() async {
        await assertScrollRequestBlocked(direction: .horizontal)
    }

    @MainActor
    private func assertScrollRequestBlocked(direction: ScrollingCapture.Direction) async {
        let session = CaptureSession()
        var requests: [Int] = []
        let view = await editingView(session: session) { requests.append($0) }
        let alphaBefore = alphaAtCenter(of: view)

        session.scrollingDirection = direction
        session.onScroll()

        XCTAssertFalse(view.isScrollingCaptureActive, "\(direction) scrolling must not start")
        XCTAssertEqual(requests, [1], "\(direction) scrolling must not request frames")
        XCTAssertTrue(session.toolbarVisible, "The editor toolbar stays available")
        XCTAssertEqual(alphaAtCenter(of: view), alphaBefore, accuracy: 0.001,
                       "Blocked scrolling leaves the frozen base visible")
    }

    @MainActor
    func testScrollingDebugEntryCannotStartCapture() async {
        var requests: [Int] = []
        let view = await editingView(session: CaptureSession()) { requests.append($0) }

        view.startScrollingForDebug()

        XCTAssertFalse(view.isScrollingCaptureActive)
        XCTAssertEqual(requests, [1])
        XCTAssertGreaterThan(alphaAtCenter(of: view), 0.9)
    }

    @MainActor
    func testScrollingDemoRouteDoesNotOpenOverlay() {
        _ = NSApplication.shared
        let coordinator = ScreenshotCoordinator()
        coordinator.beginScrollingDemo()
        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertFalse(ScreenshotAvailability.scrollingCapture)
    }
}

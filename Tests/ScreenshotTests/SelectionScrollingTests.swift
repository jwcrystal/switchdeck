import AppKit
import XCTest
@testable import SwitchDeckApp

final class SelectionScrollingTests: XCTestCase {
    @MainActor
    func testScrollingDoesNotDrawTheFrozenEditorImage() async {
        _ = NSApplication.shared
        let screen = NSScreen.screens[0]
        let session = CaptureSession()
        let source = ScrollingCaptureTests.frame(offset: 0)
        let requested = expectation(description: "Editor loads its frozen image")
        var didRequest = false
        let view = SelectionView(screen: screen, session: session) { _, _ in
            if !didRequest {
                didRequest = true
                requested.fulfill()
            }
            return source
        }
        let region = CGRect(x: 20, y: 20, width: 200, height: 160)
        view.presetSelection(region)
        await fulfillment(of: [requested], timeout: 1)
        await Task.yield()

        func alphaAtCenter() -> CGFloat {
            let bitmap = view.bitmapImageRepForCachingDisplay(in: region)!
            view.cacheDisplay(in: region, to: bitmap)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.alphaComponent
        }

        XCTAssertGreaterThan(alphaAtCenter(), 0.9, "Ordinary editing shows its captured base")
        view.startScrollingForDebug()
        XCTAssertLessThan(alphaAtCenter(), 0.01, "Scrolling must leave the selected region transparent")
        view.stopScrollingForDebug()
    }
}

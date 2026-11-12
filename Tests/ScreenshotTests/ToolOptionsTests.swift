import AppKit
import SwiftUI
import XCTest
@testable import SwitchDeckApp

final class ToolOptionsTests: XCTestCase {
    @MainActor
    func testEveryDrawingToolHasACompactSecondRow() {
        _ = NSApplication.shared
        func size(_ tool: CaptureSession.Tool) -> NSSize {
            let session = CaptureSession()
            session.tool = tool
            let host = NSHostingView(rootView: CaptureToolbarView(session: session))
            return host.fittingSize
        }
        let main = size(.select)
        for tool in CaptureSession.Tool.allCases where tool != .select {
            let expanded = size(tool)
            XCTAssertGreaterThan(expanded.height, main.height + 20, "\(tool) options must appear below")
            XCTAssertLessThanOrEqual(expanded.width, main.width + 2, "\(tool) must not widen the main toolbar")
        }
    }

    func testArrowChoicesUseDifferentPaths() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 20)
        let paths = [ArrowStyle.straight, .curved, .elbow, .sCurve].map { ArrowOptionIcon(style: $0).path(in: rect).description }
        XCTAssertEqual(Set(paths).count, 4)
    }

    @MainActor
    func testOptionalVisualSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["SWITCHDECK_UI_SNAPSHOT"] else { return }
        _ = NSApplication.shared
        let session = CaptureSession()
        session.tool = .arrow
        let host = NSHostingView(rootView: CaptureToolbarView(session: session))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import SwitchDeckApp

final class SelectedStyleTests: XCTestCase {
    private func arrow(_ color: Color = .red) -> Annotation {
        Annotation(
            shape: .arrow(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.8, y: 0.8)),
            style: AnnotationStyle(color: color)
        )
    }

    @MainActor
    func testStyleEditTargetsSelectedAnnotationAndUpdatesDefaults() {
        let session = CaptureSession()
        session.annotations = [arrow(), arrow()]
        session.selectionIndex = 0

        session.activeStyle.color = .blue

        XCTAssertEqual(session.annotations[0].color, .blue)
        XCTAssertEqual(session.annotations[1].color, .red)
        XCTAssertEqual(session.defaultStyle.color, .blue)
    }

    @MainActor
    func testStyleEditWithoutSelectionOnlyChangesDefaults() {
        let session = CaptureSession()
        session.annotations = [arrow()]

        session.activeStyle.lineWidth = 0.01

        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)
        XCTAssertEqual(session.defaultStyle.lineWidth, 0.01)
        XCTAssertFalse(session.canUndo, "editing the defaults alone is not content history")
    }

    @MainActor
    func testInvalidSelectionFallsBackToDefaultsAndDoesNotCrash() {
        let session = CaptureSession()
        session.annotations = [arrow()]
        session.selectionIndex = 9

        XCTAssertNil(session.selectedAnnotation)
        XCTAssertFalse(session.hasSelectedAnnotation)
        XCTAssertEqual(session.activeStyle, session.defaultStyle)

        session.activeStyle.color = .blue

        XCTAssertEqual(session.annotations[0].color, .red)
        XCTAssertEqual(session.defaultStyle.color, .blue)
    }

    @MainActor
    func testSelectedShapeMapsToExpectedTool() {
        let cases: [(Annotation.Shape, CaptureSession.Tool)] = [
            (.rectangle(from: .zero, to: .zero), .rectangle),
            (.ellipse(from: .zero, to: .zero), .ellipse),
            (.line(from: .zero, to: .zero), .line),
            (.arrow(from: .zero, to: .zero), .arrow),
            (.pen(points: []), .pen),
            (.highlighter(points: []), .highlighter),
            (.text("Hi", at: .zero), .text),
            (.number(1, at: .zero), .number),
            (.mosaic(from: .zero, to: .zero), .mosaic),
            (.blur(from: .zero, to: .zero), .blur),
        ]

        for (shape, tool) in cases {
            XCTAssertEqual(CaptureSession.tool(for: shape), tool)
        }

        let session = CaptureSession()
        session.tool = .select
        session.annotations = [Annotation(shape: .text("Hi", at: CGPoint(x: 0.3, y: 0.3)), style: AnnotationStyle())]
        session.selectionIndex = 0

        XCTAssertEqual(session.displayTool, .text)
        XCTAssertTrue(session.showsOptions)

        session.selectionIndex = nil
        XCTAssertEqual(session.displayTool, .select)
        XCTAssertFalse(session.showsOptions)
    }

    @MainActor
    func testSelectingAnnotationRevealsOptionsRow() {
        _ = NSApplication.shared

        func toolbarSize(selected: Bool) -> NSSize {
            let session = CaptureSession()
            session.tool = .select
            session.annotations = [arrow()]
            session.selectionIndex = selected ? 0 : nil
            return NSHostingView(rootView: CaptureToolbarView(session: session)).fittingSize
        }

        let collapsed = toolbarSize(selected: false)
        let expanded = toolbarSize(selected: true)

        XCTAssertGreaterThan(expanded.height, collapsed.height + 20)
        XCTAssertLessThanOrEqual(expanded.width, collapsed.width + 2)
    }

    @MainActor
    func testStyleBindingWritesThroughToAnnotation() {
        let session = CaptureSession()
        session.annotations = [arrow()]
        session.selectionIndex = 0

        session.styleBinding(\.lineWidth).wrappedValue = 0.012
        session.styleBinding(\.arrowStyle).wrappedValue = .elbow

        XCTAssertEqual(session.annotations[0].lineWidth, 0.012)
        XCTAssertEqual(session.annotations[0].arrowStyle, .elbow)
        XCTAssertEqual(session.defaultStyle.lineWidth, 0.012)
        XCTAssertEqual(session.defaultStyle.arrowStyle, .elbow)
    }
}

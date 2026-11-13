import AppKit
import XCTest
@testable import SwitchDeckApp

final class AnnotationHistoryTests: XCTestCase {
    private func arrow(at x: CGFloat = 0.2) -> Annotation {
        Annotation(
            shape: .arrow(from: CGPoint(x: x, y: 0.2), to: CGPoint(x: x + 0.3, y: 0.8)),
            style: AnnotationStyle()
        )
    }

    @MainActor
    private func makeSession(_ annotations: [Annotation] = []) -> CaptureSession {
        let session = CaptureSession()
        session.annotations = annotations
        return session
    }

    @MainActor
    func testUndoRestoresPreviousAnnotationStyle() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0

        session.activeStyle.color = .blue
        XCTAssertTrue(session.canUndo)

        session.undo()

        XCTAssertEqual(session.annotations[0].color, .red)
        XCTAssertNil(session.selectionIndex)
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testRedoReappliesStyle() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()

        session.redo()

        XCTAssertEqual(session.annotations[0].color, .blue)
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testUndoAfterMoveRestoresPositionNotDeletesAnnotation() {
        let original = arrow()
        let session = makeSession([original])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.annotations[0] = original.moved(by: CGPoint(x: 0.1, y: 0.1))
        session.endInteractiveChange()

        XCTAssertNotEqual(session.annotations[0], original)
        session.undo()

        XCTAssertEqual(session.annotations.count, 1)
        XCTAssertEqual(session.annotations[0], original)
    }

    @MainActor
    func testUndoAfterDeleteRestoresAnnotation() {
        let original = arrow()
        let session = makeSession([original])
        session.selectionIndex = 0

        session.recordUndoSnapshot()
        session.annotations.remove(at: 0)
        session.selectionIndex = nil

        session.undo()

        XCTAssertEqual(session.annotations, [original])
    }

    @MainActor
    func testSliderStyleChangesCoalesceIntoOneUndoStep() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        for step in 0...8 {
            session.activeStyle.lineWidth = 0.004 + CGFloat(step) * 0.001
        }
        session.endInteractiveChange()

        XCTAssertEqual(session.annotations[0].lineWidth, 0.012)

        session.undo()

        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)
        XCTAssertFalse(session.canUndo, "the whole slider drag is one undo step")
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testUndoClearsSelectionIndex() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue

        session.undo()

        XCTAssertNil(session.selectionIndex)
    }

    @MainActor
    func testCanUndoAndCanRedoFollowStacks() {
        let session = makeSession()
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)

        session.recordUndoSnapshot()
        session.annotations.append(arrow())
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)

        session.undo()
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)

        session.redo()
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testClickWithoutMovementKeepsRedo() {
        let session = makeSession([arrow()])
        session.recordUndoSnapshot()
        session.annotations.append(arrow(at: 0.5))
        session.undo()
        XCTAssertTrue(session.canRedo)

        // Selecting and releasing without moving must not add history.
        session.selectionIndex = 0
        session.beginInteractiveChange()
        session.endInteractiveChange()

        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testInteractiveChangeWithoutContentDoesNotCreateHistory() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.endInteractiveChange()

        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testSettingSameStyleValueDoesNotCreateHistoryOrClearRedo() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.selectionIndex = 0
        session.activeStyle.color = session.annotations[0].color

        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testDefaultStyleChangeDoesNotCreateContentHistory() {
        let session = makeSession([arrow()])

        session.activeStyle.color = .blue
        session.beginInteractiveChange()
        session.defaultStyle.lineWidth = 0.01
        session.endInteractiveChange()

        XCTAssertEqual(session.defaultStyle.color, .blue)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testUndoRestoresDefaultStyle() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        XCTAssertEqual(session.defaultStyle.color, .blue)

        session.undo()

        XCTAssertEqual(session.defaultStyle.color, .red)
    }

    @MainActor
    func testNewContentOperationClearsRedo() {
        let session = makeSession([arrow()])
        session.recordUndoSnapshot()
        session.annotations.append(arrow(at: 0.5))
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.recordUndoSnapshot()
        session.annotations.append(arrow(at: 0.6))

        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testHistoryKeepsAboutFiftySteps() {
        let session = makeSession()

        for step in 0..<60 {
            session.recordUndoSnapshot()
            session.annotations.append(arrow(at: CGFloat(step) / 100))
        }

        var undos = 0
        while session.canUndo, undos < 100 {
            session.undo()
            undos += 1
        }

        XCTAssertEqual(undos, 50)
        XCTAssertEqual(session.annotations.count, 10)
    }

    @MainActor
    func testUndoDuringChangedSliderUndoesTheSliderOnly() {
        let original = arrow()
        let session = makeSession([original])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.styleBinding(\.lineWidth).wrappedValue = 0.012
        XCTAssertTrue(session.canUndo, "a changed gesture is already undoable")

        session.undo()

        XCTAssertEqual(session.annotations, [original], "undo applies to the slider edit, not an older entry")
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)

        session.redo()

        XCTAssertEqual(session.annotations[0].lineWidth, 0.012)
    }

    @MainActor
    func testUndoDuringChangedGestureKeepsEarlierAnnotation() {
        let original = arrow()
        let session = makeSession()
        session.recordUndoSnapshot()
        session.annotations.append(original)
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.styleBinding(\.color).wrappedValue = .blue
        session.undo()

        XCTAssertEqual(session.annotations, [original], "the annotation itself must not be undone away")
        XCTAssertEqual(session.annotations[0].color, .red)
        XCTAssertTrue(session.canUndo, "adding the annotation is still undoable")
    }

    @MainActor
    func testRedoDuringChangedGestureInvalidatesRedoInsteadOfJumpingBranches() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.selectionIndex = 0
        session.beginInteractiveChange()
        session.styleBinding(\.lineWidth).wrappedValue = 0.012
        session.redo()

        XCTAssertEqual(session.annotations[0].color, .red, "redo must not restore the abandoned blue branch")
        XCTAssertEqual(session.annotations[0].lineWidth, 0.012)
        XCTAssertFalse(session.canRedo)
        XCTAssertTrue(session.canUndo)

        session.endInteractiveChange()
        XCTAssertFalse(session.canRedo)
    }

    @MainActor
    func testUnchangedInteractionPreservesRedo() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.selectionIndex = 0
        session.beginInteractiveChange()
        session.undo()

        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)

        session.redo()

        XCTAssertEqual(session.annotations[0].color, .blue)
    }

    @MainActor
    func testCanUndoAndCanRedoFollowPendingGesture() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)

        session.selectionIndex = 0
        session.beginInteractiveChange()
        XCTAssertTrue(session.canRedo, "merely starting a gesture does not invalidate redo")

        session.activeStyle.lineWidth = 0.012
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo, "a real in-gesture change hides redo")

        session.activeStyle.lineWidth = 0.004
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo, "reverting the gesture restores redo")

        session.endInteractiveChange()
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testInvalidRedoDuringChangedSliderKeepsCoalescing() {
        let original = arrow()
        let session = makeSession([original])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.styleBinding(\.lineWidth).wrappedValue = 0.006
        XCTAssertFalse(session.canRedo)

        session.redo()

        XCTAssertEqual(session.selectionIndex, 0, "an unavailable redo must not end the gesture")
        XCTAssertEqual(session.annotations[0].lineWidth, 0.006)

        session.styleBinding(\.lineWidth).wrappedValue = 0.008
        session.styleBinding(\.lineWidth).wrappedValue = 0.010
        session.endInteractiveChange()

        session.undo()

        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)
        XCTAssertFalse(session.canUndo, "the whole slider gesture is still one undo step")
    }

    @MainActor
    func testInvalidRedoDuringChangedGestureDoesNotJumpToOldBranch() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0
        session.activeStyle.color = .blue
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.selectionIndex = 0
        session.beginInteractiveChange()
        session.styleBinding(\.lineWidth).wrappedValue = 0.006
        XCTAssertFalse(session.canRedo)

        session.redo()
        XCTAssertEqual(session.selectionIndex, 0)
        session.styleBinding(\.lineWidth).wrappedValue = 0.010
        session.endInteractiveChange()

        session.undo()
        XCTAssertEqual(session.annotations[0].color, .red)
        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)

        session.redo()
        XCTAssertEqual(session.annotations[0].color, .red, "redo must not resurrect the abandoned branch")
        XCTAssertEqual(session.annotations[0].lineWidth, 0.010)
    }

    @MainActor
    func testUndoDuringSliderThenMoreTicksOnlyEditDefaults() {
        let session = makeSession([arrow()])
        session.selectionIndex = 0

        session.beginInteractiveChange()
        session.styleBinding(\.lineWidth).wrappedValue = 0.006
        session.undo()

        XCTAssertNil(session.selectionIndex)
        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)
        XCTAssertTrue(session.canRedo)

        session.styleBinding(\.lineWidth).wrappedValue = 0.008
        session.endInteractiveChange()

        XCTAssertEqual(session.defaultStyle.lineWidth, 0.008)
        XCTAssertEqual(session.annotations[0].lineWidth, 0.004)
        XCTAssertFalse(session.canUndo, "post-undo slider ticks without a selection are not content history")
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testKeyboardRoutingUsesUndoAndRedo() {
        _ = NSApplication.shared

        XCTAssertEqual(SelectionView.historyCommand(for: keyEvent(6, [.command])), .undo)
        XCTAssertEqual(SelectionView.historyCommand(for: keyEvent(6, [.command, .shift])), .redo)
        XCTAssertNil(SelectionView.historyCommand(for: keyEvent(6, [])))
        XCTAssertNil(SelectionView.historyCommand(for: keyEvent(0, [.command])))
        XCTAssertNil(SelectionView.historyCommand(for: keyEvent(6, [.option])))
    }

    @MainActor
    func testUndoDuringAnnotationDragStopsTheDragWritingBack() {
        _ = NSApplication.shared
        let (view, session) = makeEditingView()
        let original = annotationRect()
        session.annotations = [original]
        session.selectionIndex = 0

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 220, y: 170)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 260, y: 170)))
        XCTAssertNotEqual(session.annotations[0], original)

        view.keyDown(with: keyEvent(6, [.command]))

        XCTAssertEqual(session.annotations, [original], "the first undo returns to the pre-drag state")
        XCTAssertNil(session.selectionIndex)

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 320, y: 170)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 320, y: 170)))

        XCTAssertEqual(session.annotations, [original], "the cancelled drag must not reuse its cached original")
        XCTAssertTrue(session.canRedo)
    }

    @MainActor
    func testUndoDuringUnmovedDragKeepsRedoAndStopsLaterMovement() {
        _ = NSApplication.shared
        let (view, session) = makeEditingView()
        let first = annotationRect()
        let second = Annotation(
            shape: .rectangle(from: CGPoint(x: 0.8, y: 0.8), to: CGPoint(x: 0.9, y: 0.9)),
            style: AnnotationStyle()
        )
        session.annotations = [first]
        session.recordUndoSnapshot()
        session.annotations.append(second)
        session.selectionIndex = 0

        // Mouse down on the first annotation, no movement, then the toolbar's undo.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 220, y: 170)))
        session.onUndo()

        XCTAssertEqual(session.annotations, [first])
        XCTAssertTrue(session.canRedo)

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 320, y: 220)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 320, y: 220)))

        XCTAssertEqual(session.annotations, [first], "the cancelled click must not leave an unrecorded move")
        XCTAssertTrue(session.canRedo, "an unchanged gesture must keep redo")
    }

    @MainActor
    func testUndoDuringShapeDragDiscardsTheDraft() {
        _ = NSApplication.shared
        let (view, session) = makeEditingView()
        session.recordUndoSnapshot()
        session.annotations.append(annotationRect())
        session.tool = .rectangle

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 100)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 200, y: 160)))
        view.keyDown(with: keyEvent(6, [.command]))
        XCTAssertTrue(session.annotations.isEmpty, "the available undo runs")
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 200)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 300, y: 200)))

        XCTAssertTrue(session.annotations.isEmpty, "a cancelled drawing preview must not be committed")
        XCTAssertFalse(session.canUndo)
    }

    @MainActor
    func testInvalidUndoDuringShapeDragKeepsTheDraft() {
        _ = NSApplication.shared
        let (view, session) = makeEditingView()
        session.tool = .rectangle
        XCTAssertFalse(session.canUndo)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 100)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 200, y: 160)))
        view.keyDown(with: keyEvent(6, [.command]))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 200)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 300, y: 200)))

        XCTAssertEqual(session.annotations.count, 1, "an unavailable undo must not discard the drawing preview")
    }

    @MainActor
    func testInvalidRedoDuringAnnotationDragKeepsTheGesture() {
        _ = NSApplication.shared
        let (view, session) = makeEditingView()
        let original = annotationRect()
        session.annotations = [original]
        session.selectionIndex = 0

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 220, y: 170)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 260, y: 170)))
        let afterFirstDrag = session.annotations[0]
        XCTAssertFalse(session.canRedo)

        view.keyDown(with: keyEvent(6, [.command, .shift]))

        XCTAssertEqual(session.annotations[0], afterFirstDrag, "an unavailable redo must not end the drag")

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 170)))
        XCTAssertNotEqual(session.annotations[0], afterFirstDrag, "the drag must keep working")
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 300, y: 170)))

        session.undo()

        XCTAssertEqual(session.annotations, [original], "the whole drag stays one undo step")
    }

    @MainActor
    func testUndoDuringSelectionResizeStillReloadsBaseOnMouseUp() async {
        _ = NSApplication.shared
        let screen = NSScreen.screens[0]
        let session = CaptureSession()
        let source = ScrollingCaptureTests.frame(offset: 0)
        var requestedRects: [CGRect] = []
        let firstBase = expectation(description: "initial frozen base")
        let reloadedBase = expectation(description: "resized base reloaded")
        let view = SelectionView(screen: screen, session: session) { rect, _ in
            requestedRects.append(rect)
            if requestedRects.count == 1 { firstBase.fulfill() }
            if requestedRects.count == 2 { reloadedBase.fulfill() }
            return source
        }
        let region = CGRect(x: 20, y: 20, width: 200, height: 160)
        view.presetSelection(region)
        await fulfillment(of: [firstBase], timeout: 2)
        await Task.yield()

        session.recordUndoSnapshot()
        session.annotations.append(annotationRect())

        // Start a selection resize, then undo an annotation change mid-drag.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: region.maxX, y: region.maxY)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 240)))
        view.keyDown(with: keyEvent(6, [.command]))
        XCTAssertTrue(session.annotations.isEmpty)

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 360, y: 280)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 360, y: 280)))

        await fulfillment(of: [reloadedBase], timeout: 2)

        XCTAssertEqual(requestedRects.count, 2)
        XCTAssertEqual(requestedRects[1].width, 340, accuracy: 2, "mouse up must reload the resized selection")
        XCTAssertEqual(requestedRects[1].height, 260, accuracy: 2)
    }

    @MainActor
    private func makeEditingView() -> (SelectionView, CaptureSession) {
        let screen = NSScreen.screens[0]
        let session = CaptureSession()
        let view = SelectionView(screen: screen, session: session) { _, _ in nil }
        view.presetSelection(CGRect(x: 20, y: 20, width: 400, height: 300))
        return (view, session)
    }

    private func annotationRect() -> Annotation {
        Annotation(
            shape: .rectangle(from: CGPoint(x: 0.3, y: 0.3), to: CGPoint(x: 0.7, y: 0.7)),
            style: AnnotationStyle()
        )
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func keyEvent(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

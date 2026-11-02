import AppKit
import SwiftUI

/// A borderless sticky-note window. It behaves like a normal window unless the note is pinned on top.
final class NotePanel: NSPanel {
    static let normalMinSize = NSSize(width: 200, height: 160)

    let noteID: UUID

    init(noteID: UUID, frame: NSRect) {
        self.noteID = noteID
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        minSize = Self.normalMinSize
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func apply(alwaysOnTop: Bool, showOnAllSpaces: Bool) {
        isFloatingPanel = alwaysOnTop
        level = alwaysOnTop ? .floating : .normal
        collectionBehavior = showOnAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }

    func focusEditor() {
        makeKeyAndOrderFront(nil)
        if let textView = contentView?.firstDescendant(ofType: RichNoteTextView.self) {
            makeFirstResponder(textView)
        }
    }
}

extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}

/// Lets a SwiftUI header move the window; a double-click calls `onDoubleClick` instead.
struct WindowDragHandle: NSViewRepresentable {
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.onDoubleClick = onDoubleClick
    }

    private final class DragView: NSView {
        var onDoubleClick: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

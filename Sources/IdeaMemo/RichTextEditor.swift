import AppKit
import StickyCore
import SwiftUI

/// NSTextView with the note-taking behaviour: list shortcuts, clickable checkboxes,
/// ⌘B / ⌘I, and plain-text paste.
final class RichNoteTextView: NSTextView {
    var style = RichTextStyle(fontSize: 14, textColor: .black)

    // MARK: List typing

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String, text == " ", selectedRange().length == 0 {
            let ns = self.string as NSString
            let caret = selectedRange().location
            let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            let kind: BlockKind? = (before == "-" || before == "*") ? .bullet
                : before == "[]" ? .checkbox(checked: false) : nil
            if let kind {
                insertText(ListMarker.text(for: kind), replacementRange: NSRange(location: lineStart, length: caret - lineStart))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)

        guard let kind = ListMarker.kind(ofLine: line) else {
            super.insertNewline(sender)
            return
        }
        if (line as NSString).length <= ListMarker.length {
            // Return on an empty item ends the list.
            insertText("", replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
            return
        }
        super.insertNewline(sender)
        let next: BlockKind = { if case .checkbox = kind { return .checkbox(checked: false) } else { return .bullet } }()
        insertText(ListMarker.text(for: next), replacementRange: selectedRange())
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0 {
            let ns = string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
            if selection.location == lineStart + ListMarker.length,
               ListMarker.kind(ofLine: ns.substring(with: NSRange(location: lineStart, length: ListMarker.length))) != nil {
                insertText("", replacementRange: NSRange(location: lineStart, length: ListMarker.length))
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: Checkboxes

    override func mouseDown(with event: NSEvent) {
        if toggleCheckbox(at: event) { return }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(at event: NSEvent) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)

        let ns = string as NSString
        guard index < ns.length else { return false }
        let char = ns.substring(with: NSRange(location: index, length: 1))
        guard char == ListMarker.unchecked || char == ListMarker.checked else { return false }
        guard index == 0 || ns.character(at: index - 1) == 10 else { return false }

        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        guard layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).insetBy(dx: -4, dy: -2).contains(local) else {
            return false
        }

        let range = NSRange(location: index, length: 1)
        let replacement = char == ListMarker.unchecked ? ListMarker.checked : ListMarker.unchecked
        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
        return true
    }

    // MARK: Formatting and paste

    @objc func toggleBold(_ sender: Any?) { toggleTrait(bold: true) }
    @objc func toggleItalic(_ sender: Any?) { toggleTrait(bold: false) }

    private func toggleTrait(bold: Bool) {
        func has(_ font: NSFont?) -> Bool {
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            return traits.contains(bold ? .bold : .italic)
        }
        func flipped(_ font: NSFont?, on: Bool) -> NSFont {
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = bold ? on : traits.contains(.bold)
            let isItalic = bold ? traits.contains(.italic) : on
            return RichTextBridge.font(size: style.fontSize, bold: isBold, italic: isItalic)
        }

        let range = selectedRange()
        if range.length == 0 {
            let current = typingAttributes[.font] as? NSFont
            typingAttributes[.font] = flipped(current, on: !has(current))
            return
        }

        var allHaveTrait = true
        textStorage?.enumerateAttribute(.font, in: range) { value, _, _ in
            if !has(value as? NSFont) { allHaveTrait = false }
        }
        guard shouldChangeText(in: range, replacementString: nil), let storage = textStorage else { return }
        var runs: [(NSRange, NSFont?)] = []
        storage.enumerateAttribute(.font, in: range) { value, runRange, _ in runs.append((runRange, value as? NSFont)) }
        storage.beginEditing()
        for (runRange, font) in runs {
            storage.addAttribute(.font, value: flipped(font, on: !allHaveTrait), range: runRange)
        }
        storage.endEditing()
        didChangeText()
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

struct RichTextEditor: NSViewRepresentable {
    let initialMarkdown: String
    let fontSize: CGFloat
    let textColor: NSColor
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(style: RichTextStyle(fontSize: fontSize, textColor: textColor), onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = RichNoteTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = context.coordinator

        let style = context.coordinator.style
        textView.style = style
        textView.insertionPointColor = style.textColor
        storage.setAttributedString(
            RichTextBridge.attributedString(from: MarkdownDocument(markdown: initialMarkdown), style: style)
        )
        textView.typingAttributes = [
            .font: RichTextBridge.font(size: style.fontSize, bold: false, italic: false),
            .foregroundColor: style.textColor,
        ]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let style = RichTextStyle(fontSize: fontSize, textColor: textColor)
        guard style != coordinator.style, let textView = scroll.documentView as? RichNoteTextView,
              let storage = textView.textStorage else { return }
        coordinator.style = style
        textView.style = style
        textView.insertionPointColor = style.textColor
        RichTextBridge.restyle(storage, style: style)
        var typing = textView.typingAttributes
        typing[.foregroundColor] = style.textColor
        let traits = (typing[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        typing[.font] = RichTextBridge.font(size: style.fontSize, bold: traits.contains(.bold), italic: traits.contains(.italic))
        textView.typingAttributes = typing
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var style: RichTextStyle
        var onChange: (String) -> Void

        init(style: RichTextStyle, onChange: @escaping (String) -> Void) {
            self.style = style
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            // Restyling while an input method is composing would cancel the composition.
            if !textView.hasMarkedText() {
                RichTextBridge.restyle(storage, style: style)
                var typing = textView.typingAttributes
                typing[.foregroundColor] = style.textColor
                textView.typingAttributes = typing
            }
            onChange(RichTextBridge.document(from: storage).markdown())
        }
    }
}

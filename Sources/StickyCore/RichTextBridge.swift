import AppKit

/// List markers are real characters at the start of a line, so the editor stays plain NSTextView.
public enum ListMarker {
    public static let bullet = "•"
    public static let unchecked = "☐"
    public static let checked = "☑"

    /// UTF-16 length of a marker plus its trailing space.
    public static let length = 2

    public static func kind(ofLine line: String) -> BlockKind? {
        if line.hasPrefix(bullet + " ") { return .bullet }
        if line.hasPrefix(unchecked + " ") { return .checkbox(checked: false) }
        if line.hasPrefix(checked + " ") { return .checkbox(checked: true) }
        return nil
    }

    public static func text(for kind: BlockKind) -> String {
        switch kind {
        case .paragraph: return ""
        case .bullet: return bullet + " "
        case .checkbox(let isChecked): return (isChecked ? checked : unchecked) + " "
        }
    }
}

public struct RichTextStyle: Equatable {
    public var fontSize: CGFloat
    public var textColor: NSColor

    public init(fontSize: CGFloat, textColor: NSColor) {
        self.fontSize = fontSize
        self.textColor = textColor
    }
}

/// Converts between the Markdown model and the attributed text shown in the editor.
public enum RichTextBridge {
    public static func font(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = NSFont.systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    public static func attributedString(from document: MarkdownDocument, style: RichTextStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in document.blocks.enumerated() {
            let base: [NSAttributedString.Key: Any] = [
                .font: font(size: style.fontSize, bold: false, italic: false),
                .foregroundColor: style.textColor,
            ]
            let marker = ListMarker.text(for: block.kind)
            if !marker.isEmpty { result.append(NSAttributedString(string: marker, attributes: base)) }
            for run in block.runs {
                var attributes = base
                attributes[.font] = font(size: style.fontSize, bold: run.bold, italic: run.italic)
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if index < document.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: base))
            }
        }
        restyle(result, style: style)
        return result
    }

    public static func document(from attributed: NSAttributedString) -> MarkdownDocument {
        let text = attributed.string as NSString
        var blocks: [MarkdownBlock] = []
        var start = 0
        while true {
            let newline = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
            let end = newline.location == NSNotFound ? text.length : newline.location
            blocks.append(block(in: attributed, range: NSRange(location: start, length: end - start)))
            if newline.location == NSNotFound { break }
            start = newline.location + 1
        }
        return MarkdownDocument(blocks: blocks)
    }

    private static func block(in attributed: NSAttributedString, range: NSRange) -> MarkdownBlock {
        let line = (attributed.string as NSString).substring(with: range)
        let kind = ListMarker.kind(ofLine: line) ?? .paragraph
        let skip = kind == .paragraph ? 0 : ListMarker.length
        let body = NSRange(location: range.location + skip, length: range.length - skip)

        var runs: [InlineRun] = []
        attributed.enumerateAttribute(.font, in: body) { value, runRange, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let piece = InlineRun(
                text: (attributed.string as NSString).substring(with: runRange),
                bold: traits.contains(.bold),
                italic: traits.contains(.italic)
            )
            if var last = runs.last, last.bold == piece.bold, last.italic == piece.italic {
                last.text += piece.text
                runs[runs.count - 1] = last
            } else {
                runs.append(piece)
            }
        }
        return MarkdownBlock(kind: kind, runs: runs)
    }

    /// Re-applies size, colour, list indents and the checked-item strike-through to the whole text,
    /// keeping each run's bold/italic.
    public static func restyle(_ text: NSMutableAttributedString, style: RichTextStyle) {
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return }

        var fontRuns: [(NSRange, Bool, Bool)] = []
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            fontRuns.append((range, traits.contains(.bold), traits.contains(.italic)))
        }

        let indent = markerIndent(fontSize: style.fontSize)
        let listStyle = NSMutableParagraphStyle()
        listStyle.headIndent = indent
        listStyle.firstLineHeadIndent = 0
        let plainStyle = NSParagraphStyle.default

        text.beginEditing()
        for (range, bold, italic) in fontRuns {
            text.addAttribute(.font, value: font(size: style.fontSize, bold: bold, italic: italic), range: range)
        }
        text.addAttribute(.foregroundColor, value: style.textColor, range: full)
        text.removeAttribute(.strikethroughStyle, range: full)

        let nsText = text.string as NSString
        nsText.enumerateSubstrings(in: full, options: .byParagraphs) { line, lineRange, enclosing, _ in
            let kind = ListMarker.kind(ofLine: line ?? "")
            text.addAttribute(.paragraphStyle, value: kind == nil ? plainStyle : listStyle, range: enclosing)
            if case .checkbox(true) = kind {
                let body = NSRange(
                    location: lineRange.location + ListMarker.length,
                    length: max(0, lineRange.length - ListMarker.length)
                )
                if body.length > 0 {
                    text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                    text.addAttribute(.foregroundColor, value: style.textColor.withAlphaComponent(0.55), range: body)
                }
            }
        }
        text.endEditing()
    }

    public static func markerIndent(fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let widest = [ListMarker.bullet, ListMarker.unchecked, ListMarker.checked]
            .map { NSAttributedString(string: $0 + " ", attributes: [.font: font]).size().width }
            .max() ?? fontSize
        return ceil(widest)
    }
}

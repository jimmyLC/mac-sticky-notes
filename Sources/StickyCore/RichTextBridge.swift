import AppKit

/// List markers are real characters at the start of a line, so the editor stays plain NSTextView.
public enum ListMarker {
    public static let bullet = "•"
    public static let unchecked = "☐"
    public static let checked = "☑"

    /// The marker at the start of `line`, if any, with its length in UTF-16 units (including the space).
    public static func parse(_ line: String) -> (kind: BlockKind, length: Int)? {
        if line.hasPrefix(bullet + " ") { return (.bullet, 2) }
        if line.hasPrefix(unchecked + " ") { return (.checkbox(checked: false), 2) }
        if line.hasPrefix(checked + " ") { return (.checkbox(checked: true), 2) }
        let digits = line.prefix { $0 >= "0" && $0 <= "9" }
        if (1...3).contains(digits.count), let number = Int(digits), line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered(number), digits.count + 2)
        }
        return nil
    }

    public static func kind(ofLine line: String) -> BlockKind? { parse(line)?.kind }

    public static func text(for kind: BlockKind) -> String {
        switch kind {
        case .paragraph: return ""
        case .bullet: return bullet + " "
        case .numbered(let number): return "\(number). "
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
        let parsed = ListMarker.parse(line)
        let skip = parsed?.length ?? 0
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
        return MarkdownBlock(kind: parsed?.kind ?? .paragraph, runs: runs)
    }

    // MARK: Numbering

    /// Makes consecutive numbered lines count up from the first one (1. 2. 3.). Returns the new
    /// caret position when the text changed, otherwise nil.
    @discardableResult
    public static func renumber(_ text: NSMutableAttributedString, caret: Int) -> Int? {
        let ns = text.string as NSString
        var edits: [(range: NSRange, replacement: String)] = []
        var expected: Int?

        var start = 0
        while true {
            let newline = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            let end = newline.location == NSNotFound ? ns.length : newline.location
            let line = ns.substring(with: NSRange(location: start, length: end - start))
            if let parsed = ListMarker.parse(line), case .numbered(let number) = parsed.kind {
                let target = expected ?? max(number, 1)
                expected = target + 1
                if number != target {
                    edits.append((NSRange(location: start, length: parsed.length), "\(target). "))
                }
            } else {
                expected = nil
            }
            if newline.location == NSNotFound { break }
            start = newline.location + 1
        }
        guard !edits.isEmpty else { return nil }

        var newCaret = caret
        for edit in edits {
            let delta = (edit.replacement as NSString).length - edit.range.length
            if NSMaxRange(edit.range) <= caret {
                newCaret += delta
            } else if edit.range.location < caret {
                newCaret = edit.range.location + (edit.replacement as NSString).length
            }
        }
        text.beginEditing()
        for edit in edits.reversed() { text.replaceCharacters(in: edit.range, with: edit.replacement) }
        text.endEditing()
        return max(newCaret, 0)
    }

    // MARK: Styling

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

        var indentStyles: [CGFloat: NSParagraphStyle] = [:]
        func listStyle(indent: CGFloat) -> NSParagraphStyle {
            if let cached = indentStyles[indent] { return cached }
            let style = NSMutableParagraphStyle()
            style.headIndent = indent
            style.firstLineHeadIndent = 0
            indentStyles[indent] = style
            return style
        }
        let plainStyle = NSParagraphStyle.default
        let symbolIndent = markerIndent(fontSize: style.fontSize)
        let measuringFont = NSFont.systemFont(ofSize: style.fontSize)

        text.beginEditing()
        for (range, bold, italic) in fontRuns {
            text.addAttribute(.font, value: font(size: style.fontSize, bold: bold, italic: italic), range: range)
        }
        text.addAttribute(.foregroundColor, value: style.textColor, range: full)
        text.removeAttribute(.strikethroughStyle, range: full)

        let nsText = text.string as NSString
        nsText.enumerateSubstrings(in: full, options: .byParagraphs) { line, lineRange, enclosing, _ in
            guard let parsed = ListMarker.parse(line ?? "") else {
                text.addAttribute(.paragraphStyle, value: plainStyle, range: enclosing)
                return
            }
            let indent: CGFloat
            if case .numbered = parsed.kind {
                let prefix = (nsText.substring(with: NSRange(location: lineRange.location, length: parsed.length)))
                indent = ceil(NSAttributedString(string: prefix, attributes: [.font: measuringFont]).size().width)
            } else {
                indent = symbolIndent
            }
            text.addAttribute(.paragraphStyle, value: listStyle(indent: indent), range: enclosing)
            if case .checkbox(true) = parsed.kind {
                let body = NSRange(
                    location: lineRange.location + parsed.length,
                    length: max(0, lineRange.length - parsed.length)
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

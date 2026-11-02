import Foundation

public struct InlineRun: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool

    public init(text: String, bold: Bool = false, italic: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
    }
}

public enum BlockKind: Equatable, Sendable {
    case paragraph
    case bullet
    case checkbox(checked: Bool)
}

public struct MarkdownBlock: Equatable, Sendable {
    public var kind: BlockKind
    public var runs: [InlineRun]

    public init(kind: BlockKind, runs: [InlineRun] = []) {
        self.kind = kind
        self.runs = runs
    }

    public var plainText: String { runs.map(\.text).joined() }
}

/// The small Markdown subset the app supports: bold, italic, `- ` bullets and `- [ ]` checkboxes.
/// One block per line, so a note is always a list of lines.
public struct MarkdownDocument: Equatable, Sendable {
    public var blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks.isEmpty ? [MarkdownBlock(kind: .paragraph)] : blocks
    }

    public init(markdown: String) {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        self.init(blocks: lines.map { MarkdownDocument.parseLine(String($0)) })
    }

    public var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    public func markdown() -> String {
        blocks.map(MarkdownDocument.serialize).joined(separator: "\n")
    }

    // MARK: Parsing

    private static func parseLine(_ line: String) -> MarkdownBlock {
        let checkboxes: [(prefix: String, checked: Bool)] = [
            ("- [ ]", false), ("- [x]", true), ("- [X]", true),
        ]
        for (prefix, checked) in checkboxes {
            if line == prefix {
                return MarkdownBlock(kind: .checkbox(checked: checked))
            }
            if line.hasPrefix(prefix + " ") {
                let rest = String(line.dropFirst(prefix.count + 1))
                return MarkdownBlock(kind: .checkbox(checked: checked), runs: parseInline(rest))
            }
        }
        if line.hasPrefix("- ") {
            return MarkdownBlock(kind: .bullet, runs: parseInline(String(line.dropFirst(2))))
        }
        return MarkdownBlock(kind: .paragraph, runs: parseInline(line))
    }

    private enum Event {
        case text(String)
        case bold
        case italic
    }

    static func parseInline(_ source: String) -> [InlineRun] {
        let chars = Array(source)
        var events: [Event] = []
        var buffer = ""
        var index = 0

        func flush() {
            if !buffer.isEmpty { events.append(.text(buffer)); buffer = "" }
        }

        while index < chars.count {
            let char = chars[index]
            if char == "\\", index + 1 < chars.count, "\\*-".contains(chars[index + 1]) {
                buffer.append(chars[index + 1])
                index += 2
                continue
            }
            if char == "*" {
                var count = 0
                while index + count < chars.count, chars[index + count] == "*" { count += 1 }
                flush()
                var rest = count
                while rest >= 3 { events.append(.bold); events.append(.italic); rest -= 3 }
                if rest == 2 { events.append(.bold) } else if rest == 1 { events.append(.italic) }
                index += count
                continue
            }
            buffer.append(char)
            index += 1
        }
        flush()

        // A marker without a partner stays literal text.
        for (isBold, literal) in [(true, "**"), (false, "*")] {
            let positions = events.indices.filter {
                switch events[$0] {
                case .bold: return isBold
                case .italic: return !isBold
                case .text: return false
                }
            }
            if positions.count % 2 == 1, let last = positions.last {
                events[last] = .text(literal)
            }
        }

        var runs: [InlineRun] = []
        var bold = false
        var italic = false
        for event in events {
            switch event {
            case .bold: bold.toggle()
            case .italic: italic.toggle()
            case .text(let text):
                if var last = runs.last, last.bold == bold, last.italic == italic {
                    last.text += text
                    runs[runs.count - 1] = last
                } else {
                    runs.append(InlineRun(text: text, bold: bold, italic: italic))
                }
            }
        }
        return runs
    }

    // MARK: Serializing

    private static func serialize(_ block: MarkdownBlock) -> String {
        var inline = serializeInline(block.runs)
        switch block.kind {
        case .paragraph:
            // A paragraph that would otherwise read back as a list item.
            if inline.hasPrefix("- ") { inline = "\\" + inline }
            return inline
        case .bullet:
            return "- " + inline
        case .checkbox(let checked):
            return (checked ? "- [x] " : "- [ ] ") + inline
        }
    }

    static func serializeInline(_ runs: [InlineRun]) -> String {
        var out = ""
        var bold = false
        var italic = false

        func emitToggles(boldChanged: Bool, italicChanged: Bool) {
            if boldChanged && italicChanged { out += "***" }
            else if boldChanged { out += "**" }
            else if italicChanged { out += "*" }
        }

        for run in runs where !run.text.isEmpty {
            emitToggles(boldChanged: run.bold != bold, italicChanged: run.italic != italic)
            bold = run.bold
            italic = run.italic
            out += run.text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "*", with: "\\*")
        }
        emitToggles(boldChanged: bold, italicChanged: italic)
        return out
    }
}

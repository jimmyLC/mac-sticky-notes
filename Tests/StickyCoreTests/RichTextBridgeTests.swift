import AppKit
import XCTest
@testable import StickyCore

final class RichTextBridgeTests: XCTestCase {
    private let style = RichTextStyle(fontSize: 14, textColor: .black)

    private func roundTrip(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let attributed = RichTextBridge.attributedString(from: MarkdownDocument(markdown: markdown), style: style)
        XCTAssertEqual(RichTextBridge.document(from: attributed).markdown(), markdown, file: file, line: line)
    }

    func testMarkdownSurvivesTheEditorRepresentation() {
        roundTrip("")
        roundTrip("plain text")
        roundTrip("**bold** *italic* ***both***")
        roundTrip("- bullet\n- [ ] open\n- [x] done")
        roundTrip("title\n\n- one\n- two\n\nend\n")
        roundTrip("中文 **粗體** 與 *斜體*")
    }

    func testMarkersAreShownAsCharacters() {
        let attributed = RichTextBridge.attributedString(
            from: MarkdownDocument(markdown: "- a\n- [ ] b\n- [x] c"), style: style
        )
        XCTAssertEqual(attributed.string, "• a\n☐ b\n☑ c")
    }

    func testBoldRunsGetBoldFont() {
        let attributed = RichTextBridge.attributedString(from: MarkdownDocument(markdown: "a **b**"), style: style)
        let plain = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bold = attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(plain?.fontDescriptor.symbolicTraits.contains(.bold), false)
        XCTAssertEqual(bold?.fontDescriptor.symbolicTraits.contains(.bold), true)
    }

    func testCheckedItemsAreStruckThrough() {
        let attributed = RichTextBridge.attributedString(from: MarkdownDocument(markdown: "- [x] done"), style: style)
        XCTAssertNotNil(attributed.attribute(.strikethroughStyle, at: 3, effectiveRange: nil))
        XCTAssertNil(attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
    }

    func testRestyleChangesSizeAndColorButKeepsBold() {
        let attributed = NSMutableAttributedString(
            attributedString: RichTextBridge.attributedString(from: MarkdownDocument(markdown: "a **b**"), style: style)
        )
        RichTextBridge.restyle(attributed, style: RichTextStyle(fontSize: 18, textColor: .white))
        let font = attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 18)
        XCTAssertEqual(font?.fontDescriptor.symbolicTraits.contains(.bold), true)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .white)
        XCTAssertEqual(RichTextBridge.document(from: attributed).markdown(), "a **b**")
    }

    func testListLinesGetHangingIndent() {
        let attributed = RichTextBridge.attributedString(from: MarkdownDocument(markdown: "x\n- item"), style: style)
        let plain = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let list = attributed.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(plain?.headIndent ?? 0, 0)
        XCTAssertGreaterThan(list?.headIndent ?? 0, 0)
    }
}

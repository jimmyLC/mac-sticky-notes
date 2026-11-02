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
        roundTrip("1. a\n2. b\n3. **c**\n\n- x")
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

    // MARK: Numbering

    private func renumbered(_ text: String, caret: Int = 0) -> (String, Int?) {
        let attributed = NSMutableAttributedString(string: text)
        let newCaret = RichTextBridge.renumber(attributed, caret: caret)
        return (attributed.string, newCaret)
    }

    func testRenumberCountsUpFromTheFirstLine() {
        XCTAssertEqual(renumbered("1. a\n1. b\n7. c").0, "1. a\n2. b\n3. c")
        XCTAssertEqual(renumbered("4. a\n9. b").0, "4. a\n5. b")
    }

    func testRenumberRestartsAfterABreak() {
        XCTAssertEqual(renumbered("1. a\n2. b\n\n2. c\n2. d").0, "1. a\n2. b\n\n2. c\n3. d")
        XCTAssertEqual(renumbered("1. a\ntext\n1. b").0, "1. a\ntext\n1. b")
    }

    func testRenumberLeavesCorrectTextAlone() {
        let (text, caret) = renumbered("1. a\n2. b")
        XCTAssertEqual(text, "1. a\n2. b")
        XCTAssertNil(caret)
    }

    func testRenumberKeepsTheCaretOnItsText() {
        // The caret is in "c" on the third line; the line above grows from "9." to "10.".
        let (text, caret) = renumbered("9. a\n9. b\n9. c", caret: 14)
        XCTAssertEqual(text, "9. a\n10. b\n11. c")
        XCTAssertEqual(caret, 16)
    }

    func testNumberedLinesGetAHangingIndentThatFitsTheirNumber() {
        let attributed = RichTextBridge.attributedString(from: MarkdownDocument(markdown: "9. a\n10. b"), style: style)
        let first = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let second = attributed.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(second?.headIndent ?? 0, first?.headIndent ?? 0)
    }
}

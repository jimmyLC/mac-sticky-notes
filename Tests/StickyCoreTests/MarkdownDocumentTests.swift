import XCTest
@testable import StickyCore

final class MarkdownDocumentTests: XCTestCase {
    private func roundTrip(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(MarkdownDocument(markdown: markdown).markdown(), markdown, file: file, line: line)
    }

    func testParsesBlockKinds() {
        let doc = MarkdownDocument(markdown: "plain\n- item\n- [ ] todo\n- [x] done")
        XCTAssertEqual(doc.blocks.map(\.kind), [.paragraph, .bullet, .checkbox(checked: false), .checkbox(checked: true)])
        XCTAssertEqual(doc.blocks.map(\.plainText), ["plain", "item", "todo", "done"])
    }

    func testParsesBoldAndItalic() {
        let doc = MarkdownDocument(markdown: "a **b** *c* ***d***")
        XCTAssertEqual(doc.blocks[0].runs, [
            InlineRun(text: "a "),
            InlineRun(text: "b", bold: true),
            InlineRun(text: " "),
            InlineRun(text: "c", italic: true),
            InlineRun(text: " "),
            InlineRun(text: "d", bold: true, italic: true),
        ])
    }

    func testRoundTrips() {
        roundTrip("")
        roundTrip("hello")
        roundTrip("line one\n\nline three")
        roundTrip("trailing newline\n")
        roundTrip("**bold** and *italic* and ***both***")
        roundTrip("- bullet\n- [ ] open\n- [x] closed")
        roundTrip("- [ ] ")
        roundTrip("**bold *and italic* still bold**")
        roundTrip("bold then **b***i*")
    }

    func testEscapesLiteralAsterisksAndBackslashes() {
        let doc = MarkdownDocument(blocks: [
            MarkdownBlock(kind: .paragraph, runs: [InlineRun(text: "2 * 3 \\ 4")]),
        ])
        let markdown = doc.markdown()
        XCTAssertEqual(markdown, "2 \\* 3 \\\\ 4")
        XCTAssertEqual(MarkdownDocument(markdown: markdown), doc)
    }

    func testParagraphStartingWithDashIsEscapedSoItStaysAParagraph() {
        let doc = MarkdownDocument(blocks: [
            MarkdownBlock(kind: .paragraph, runs: [InlineRun(text: "- not a list")]),
        ])
        let markdown = doc.markdown()
        XCTAssertEqual(markdown, "\\- not a list")
        XCTAssertEqual(MarkdownDocument(markdown: markdown), doc)
    }

    func testUnmatchedMarkersStayLiteral() {
        let doc = MarkdownDocument(markdown: "5 ** 2 and *oops")
        XCTAssertEqual(doc.plainText, "5 ** 2 and *oops")
        XCTAssertTrue(doc.blocks[0].runs.allSatisfy { !$0.bold && !$0.italic })
    }

    func testWindowsLineEndingsAreNormalized() {
        XCTAssertEqual(MarkdownDocument(markdown: "a\r\nb").plainText, "a\nb")
    }

    func testEmptyDocumentHasOneEmptyParagraph() {
        XCTAssertEqual(MarkdownDocument(markdown: "").blocks.count, 1)
    }
}

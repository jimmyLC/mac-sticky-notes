import XCTest
@testable import StickyCore

final class NoteStoreTests: XCTestCase {
    private var root: URL!
    private var store: NoteStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StickyCoreTests-\(UUID().uuidString)")
        store = try NoteStore(directory: root.appendingPathComponent("Notes"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeNote(_ markdown: String = "hi", color: NoteColor = .yellow) -> Note {
        Note(markdown: markdown, color: color, frame: NoteFrame(x: 10, y: 20, width: 260, height: 300))
    }

    func testSaveAndLoadRoundTrip() throws {
        var note = makeNote("**hello**", color: NoteColor(hex: "#336699"))
        note.alwaysOnTop = true
        note.showOnAllSpaces = false
        note.isCollapsed = true
        try store.save(note)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].markdown, "**hello**")
        XCTAssertEqual(loaded[0].color.hex, "#336699")
        XCTAssertTrue(loaded[0].alwaysOnTop)
        XCTAssertFalse(loaded[0].showOnAllSpaces)
        XCTAssertTrue(loaded[0].isCollapsed)
        XCTAssertEqual(loaded[0].frame, note.frame)
    }

    func testCorruptFileDoesNotAffectOthers() throws {
        let good = makeNote("good")
        try store.save(good)
        try "not json".write(to: store.directory.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadAll().map(\.id), [good.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("broken.json").path))
    }

    func testDeleteFile() throws {
        let note = makeNote()
        try store.save(note)
        try store.deleteFile(id: note.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testPurgesOnlyTrashOlderThanThirtyDays() throws {
        let now = Date()
        var old = makeNote("old")
        old.deletedAt = now.addingTimeInterval(-31 * 86_400)
        var recent = makeNote("recent")
        recent.deletedAt = now.addingTimeInterval(-29 * 86_400)
        let live = makeNote("live")
        for note in [old, recent, live] { try store.save(note) }

        let purged = store.purgeExpiredTrash(notes: [old, recent, live], now: now)
        XCTAssertEqual(purged, [old.id])
        XCTAssertEqual(Set(store.loadAll().map(\.id)), [recent.id, live.id])
    }

    func testBackupRunsOncePerDayAndKeepsSeven() throws {
        try store.save(makeNote())
        let backups = root.appendingPathComponent("Backups")
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for day in 0..<9 {
            try store.backupIfNeeded(now: start.addingTimeInterval(Double(day) * 86_400), backupsDirectory: backups)
        }
        try store.backupIfNeeded(now: start.addingTimeInterval(8 * 86_400), backupsDirectory: backups)

        let folders = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(folders.count, NoteStore.backupsToKeep)
        let newest = folders.sorted().last!
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.appendingPathComponent(newest).path)
        XCTAssertEqual(files.count, 1)
    }

    func testExportWritesMarkdownFilesWithUniqueNames() throws {
        let notes = [makeNote("Shopping\n- [ ] milk"), makeNote("Shopping\n- eggs"), makeNote("")]
        let out = root.appendingPathComponent("Export")
        let count = try store.exportMarkdown(notes: notes, to: out)
        XCTAssertEqual(count, 3)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(names, ["Note.md", "Shopping-2.md", "Shopping.md"])
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("Shopping.md"), encoding: .utf8), "Shopping\n- [ ] milk")
    }
}

final class NoteModelTests: XCTestCase {
    private func note(_ markdown: String, color: NoteColor = .yellow, created: TimeInterval = 0, modified: TimeInterval = 0) -> Note {
        Note(
            markdown: markdown, color: color,
            frame: NoteFrame(x: 0, y: 0, width: 1, height: 1),
            createdAt: Date(timeIntervalSince1970: created), modifiedAt: Date(timeIntervalSince1970: modified)
        )
    }

    func testTitleIsFirstNonEmptyLineWithoutMarkers() {
        XCTAssertEqual(note("\n\n**Plan** the week\nmore").title, "Plan the week")
        XCTAssertEqual(note("- [ ] buy milk").title, "buy milk")
        XCTAssertEqual(note("").title, "")
    }

    func testPreviewKeepsListMarkers() {
        XCTAssertEqual(note("Todo\n- a\n- [ ] b\n- [x] **c**").previewText, "Todo\n• a\n☐ b\n☑ c")
    }

    func testBlankDetection() {
        XCTAssertTrue(note("  \n \n").isBlank)
        XCTAssertFalse(note("x").isBlank)
    }

    func testDecodingFillsMissingFieldsWithDefaults() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#
        let decoded = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color, .yellow)
        XCTAssertTrue(decoded.showOnAllSpaces)
        XCTAssertFalse(decoded.alwaysOnTop)
        XCTAssertEqual(decoded.markdown, "")
    }

    func testQueryFiltersByTextAndColorAndSorts() {
        let notes = [
            note("Groceries", color: .yellow, created: 1, modified: 30),
            note("Groceries for party", color: .pink, created: 3, modified: 10),
            note("Work notes", color: .pink, created: 2, modified: 20),
        ]
        XCTAssertEqual(NoteQuery(text: "grocer").apply(to: notes).count, 2)
        XCTAssertEqual(NoteQuery(color: .pink).apply(to: notes).count, 2)
        XCTAssertEqual(NoteQuery(text: "grocer", color: .pink).apply(to: notes).map(\.markdown), ["Groceries for party"])
        XCTAssertEqual(NoteQuery(sort: .modifiedDescending).apply(to: notes).map(\.markdown),
                       ["Groceries", "Work notes", "Groceries for party"])
        XCTAssertEqual(NoteQuery(sort: .createdDescending).apply(to: notes).map(\.markdown),
                       ["Groceries for party", "Work notes", "Groceries"])
    }
}

final class NoteColorTests: XCTestCase {
    func testPresetsMatchReferencePalette() {
        XCTAssertEqual(NoteColor.presets.map(\.hex), ["#FFF299", "#FFD9E6", "#D9EBFF", "#D9F7D9"])
    }

    func testNormalizationAndFallback() {
        XCTAssertEqual(NoteColor(hex: "abc").hex, "#AABBCC")
        XCTAssertEqual(NoteColor(hex: "#ff0000").hex, "#FF0000")
        XCTAssertEqual(NoteColor(hex: "nonsense").hex, "#FFF299")
    }

    func testRGBInitRoundTrips() {
        XCTAssertEqual(NoteColor(red: 1, green: 0, blue: 0.5).hex, "#FF0080")
    }

    func testTextContrast() {
        XCTAssertFalse(NoteColor.yellow.prefersLightText)
        XCTAssertTrue(NoteColor(hex: "#102030").prefersLightText)
    }

    func testCodableAsPlainString() throws {
        let data = try JSONEncoder().encode([NoteColor.pink])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"#FFD9E6\"]")
    }
}

import Foundation

public struct NoteFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let defaultWidth = 260.0
    public static let defaultHeight = 300.0
}

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// The note body as Markdown (the on-disk source of truth).
    public var markdown: String
    public var color: NoteColor
    public var frame: NoteFrame
    public var alwaysOnTop: Bool
    public var showOnAllSpaces: Bool
    /// Closed with the ✕ button: still listed in the manager, not shown on the desktop.
    public var isCollapsed: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        markdown: String = "",
        color: NoteColor = .default,
        frame: NoteFrame,
        alwaysOnTop: Bool = false,
        showOnAllSpaces: Bool = true,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.markdown = markdown
        self.color = color
        self.frame = frame
        self.alwaysOnTop = alwaysOnTop
        self.showOnAllSpaces = showOnAllSpaces
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, markdown, color, frame, alwaysOnTop, showOnAllSpaces, isCollapsed
        case createdAt, modifiedAt, deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try c.decode(UUID.self, forKey: .id)
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        color = try c.decodeIfPresent(NoteColor.self, forKey: .color) ?? .default
        frame = try c.decodeIfPresent(NoteFrame.self, forKey: .frame)
            ?? NoteFrame(x: 100, y: 100, width: NoteFrame.defaultWidth, height: NoteFrame.defaultHeight)
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        showOnAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces) ?? true
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? now
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public var plainText: String { MarkdownDocument(markdown: markdown).plainText }

    /// Plain text with list markers (• ☐ ☑), as shown on a manager card.
    public var previewText: String {
        MarkdownDocument(markdown: markdown).blocks
            .map { ListMarker.text(for: $0.kind) + $0.plainText }
            .joined(separator: "\n")
    }

    /// First non-empty line, shown in the note header and the manager.
    public var title: String {
        for line in plainText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(40)) }
        }
        return ""
    }

    public var isBlank: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isInTrash: Bool { deletedAt != nil }
}

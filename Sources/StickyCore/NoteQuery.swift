import Foundation

public enum NoteSort: String, CaseIterable, Sendable {
    case modifiedDescending
    case createdDescending
}

/// Search text, colour filter and sort order used by the manager window.
public struct NoteQuery: Equatable, Sendable {
    public var text: String
    public var color: NoteColor?
    public var sort: NoteSort

    public init(text: String = "", color: NoteColor? = nil, sort: NoteSort = .modifiedDescending) {
        self.text = text
        self.color = color
        self.sort = sort
    }

    public func apply(to notes: [Note]) -> [Note] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = notes.filter { note in
            if let color, note.color != color { return false }
            if needle.isEmpty { return true }
            return note.plainText.localizedStandardContains(needle)
        }
        switch sort {
        case .modifiedDescending:
            return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
        case .createdDescending:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }
}

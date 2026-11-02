import Foundation

/// One JSON file per note, so a damaged file never takes the others down with it.
public final class NoteStore {
    public static let trashRetentionDays = 30
    public static let backupsToKeep = 7

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Files that cannot be decoded are skipped, not deleted.
    public func loadAll() -> [Note] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Note.self, from: data)
            }
    }

    public func save(_ note: Note) throws {
        let data = try encoder.encode(note)
        try data.write(to: fileURL(for: note.id), options: .atomic)
    }

    public func deleteFile(id: UUID) throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Deletes notes that have sat in the trash longer than the retention period.
    @discardableResult
    public func purgeExpiredTrash(notes: [Note], now: Date = Date()) -> [UUID] {
        let limit = TimeInterval(Self.trashRetentionDays * 24 * 60 * 60)
        var purged: [UUID] = []
        for note in notes {
            guard let deletedAt = note.deletedAt, now.timeIntervalSince(deletedAt) > limit else { continue }
            if (try? deleteFile(id: note.id)) != nil { purged.append(note.id) }
        }
        return purged
    }

    // MARK: Backup

    /// Copies all note files into `Backups/yyyy-MM-dd` next to the notes folder, once per day,
    /// and keeps only the newest `backupsToKeep` folders.
    public func backupIfNeeded(now: Date = Date(), backupsDirectory: URL? = nil) throws {
        let root = backupsDirectory ?? directory.deletingLastPathComponent().appendingPathComponent("Backups")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = root.appendingPathComponent(formatter.string(from: now), isDirectory: true)

        if !fileManager.fileExists(atPath: today.path) {
            try fileManager.createDirectory(at: today, withIntermediateDirectories: true)
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                try fileManager.copyItem(at: file, to: today.appendingPathComponent(file.lastPathComponent))
            }
        }

        let folders = ((try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in folders.dropFirst(Self.backupsToKeep) {
            try? fileManager.removeItem(at: stale)
        }
    }

    // MARK: Export

    /// Writes each note as a `.md` file into `folder`. Returns how many files were written.
    @discardableResult
    public func exportMarkdown(notes: [Note], to folder: URL) throws -> Int {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var used = Set<String>()
        var written = 0
        for note in notes {
            var base = note.title
                .components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            if base.isEmpty { base = "Note" }
            var name = base
            var counter = 2
            while used.contains(name.lowercased()) {
                name = "\(base)-\(counter)"
                counter += 1
            }
            used.insert(name.lowercased())
            let url = folder.appendingPathComponent(name + ".md")
            try note.markdown.write(to: url, atomically: true, encoding: .utf8)
            written += 1
        }
        return written
    }
}

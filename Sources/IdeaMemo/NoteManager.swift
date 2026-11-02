import AppKit
import StickyCore
import SwiftUI

/// Owns every note, its desktop window, and persistence.
@MainActor
final class NoteManager: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var notes: [Note] = []

    let store: NoteStore
    let settings: AppSettings
    private var panels: [UUID: NotePanel] = [:]
    private var dirty = Set<UUID>()
    private var saveWork: DispatchWorkItem?

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()
    }

    // MARK: Lookup

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }
    var activeNotes: [Note] { notes.filter { !$0.isInTrash } }
    var trashedNotes: [Note] { notes.filter(\.isInTrash) }

    private func index(of id: UUID) -> Int? { notes.firstIndex { $0.id == id } }

    // MARK: Lifecycle

    func start() {
        notes = store.loadAll()
        let purged = Set(store.purgeExpiredTrash(notes: notes))
        notes.removeAll { purged.contains($0.id) }
        try? store.backupIfNeeded()
        for note in notes where !note.isInTrash && !note.isCollapsed {
            openPanel(for: note.id, focus: false)
        }
    }

    func flush() {
        saveWork?.cancel()
        saveNow()
    }

    // MARK: Creating

    @discardableResult
    func createNote() -> UUID {
        let note = Note(frame: defaultFrame())
        notes.append(note)
        persist(note.id)
        openPanel(for: note.id, focus: true)
        return note.id
    }

    private func defaultFrame() -> NoteFrame {
        // New notes appear on the display the pointer is on.
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let offset = Double(28 * (panels.count % 6))
        return NoteFrame(
            x: visible.maxX - NoteFrame.defaultWidth - 40 - offset,
            y: visible.maxY - NoteFrame.defaultHeight - 40 - offset,
            width: NoteFrame.defaultWidth,
            height: NoteFrame.defaultHeight
        )
    }

    // MARK: Editing

    func setMarkdown(_ id: UUID, _ markdown: String) {
        guard let i = index(of: id), notes[i].markdown != markdown else { return }
        notes[i].markdown = markdown
        notes[i].modifiedAt = Date()
        persist(id)
    }

    func setColor(_ id: UUID, _ color: NoteColor) {
        guard let i = index(of: id), notes[i].color != color else { return }
        notes[i].color = color
        notes[i].modifiedAt = Date()
        persist(id)
    }

    func togglePin(_ id: UUID) {
        guard let i = index(of: id) else { return }
        notes[i].alwaysOnTop.toggle()
        applyWindowFlags(id)
        persist(id)
    }

    func toggleAllSpaces(_ id: UUID) {
        guard let i = index(of: id) else { return }
        notes[i].showOnAllSpaces.toggle()
        applyWindowFlags(id)
        persist(id)
    }

    func updateFrame(_ id: UUID, _ rect: NSRect) {
        guard let i = index(of: id) else { return }
        notes[i].frame = NoteFrame(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        persist(id)
    }

    // MARK: Showing and hiding

    /// ✕ on a note: keep it in the manager, drop it from the desktop. Blank notes are discarded.
    func collapse(_ id: UUID) {
        guard let i = index(of: id) else { return }
        if notes[i].isBlank {
            deletePermanently(id)
            return
        }
        notes[i].isCollapsed = true
        closePanel(id)
        persist(id)
    }

    func reopen(_ id: UUID) {
        guard let i = index(of: id), !notes[i].isInTrash else { return }
        notes[i].isCollapsed = false
        persist(id)
        openPanel(for: id, focus: true)
    }

    func showAll() {
        for note in activeNotes {
            if let i = index(of: note.id), notes[i].isCollapsed {
                notes[i].isCollapsed = false
                persist(note.id)
            }
            openPanel(for: note.id, focus: false)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Trash

    func moveToTrash(_ id: UUID) {
        guard let i = index(of: id) else { return }
        if notes[i].isBlank {
            deletePermanently(id)
            return
        }
        notes[i].deletedAt = Date()
        closePanel(id)
        persist(id)
    }

    func restore(_ id: UUID) {
        guard let i = index(of: id) else { return }
        notes[i].deletedAt = nil
        notes[i].isCollapsed = false
        notes[i].modifiedAt = Date()
        persist(id)
        openPanel(for: id, focus: false)
    }

    func deletePermanently(_ id: UUID) {
        closePanel(id)
        dirty.remove(id)
        notes.removeAll { $0.id == id }
        try? store.deleteFile(id: id)
    }

    func emptyTrash() {
        for note in trashedNotes { deletePermanently(note.id) }
    }

    // MARK: Export

    @discardableResult
    func exportAll(to folder: URL) throws -> Int {
        try store.exportMarkdown(notes: activeNotes.sorted { $0.createdAt < $1.createdAt }, to: folder)
    }

    // MARK: Panels

    private func openPanel(for id: UUID, focus: Bool) {
        guard let note = note(id) else { return }
        if let existing = panels[id] {
            focus ? existing.focusEditor() : existing.orderFrontRegardless()
            return
        }

        let panel = NotePanel(noteID: id, frame: visibleFrame(for: note.frame))
        panel.delegate = self
        let host = NSHostingView(rootView: NoteView(manager: self, settings: settings, noteID: id))
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.cornerRadius = 4
        host.layer?.masksToBounds = true
        panel.contentView = host
        panel.apply(alwaysOnTop: note.alwaysOnTop, showOnAllSpaces: note.showOnAllSpaces)
        panels[id] = panel

        if focus {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { panel.focusEditor() }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func closePanel(_ id: UUID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func applyWindowFlags(_ id: UUID) {
        guard let note = note(id), let panel = panels[id] else { return }
        panel.apply(alwaysOnTop: note.alwaysOnTop, showOnAllSpaces: note.showOnAllSpaces)
    }

    /// A saved frame can end up off-screen after a display is unplugged.
    private func visibleFrame(for frame: NoteFrame) -> NSRect {
        let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { return rect }
        let fallback = defaultFrame()
        return NSRect(x: fallback.x, y: fallback.y, width: frame.width, height: frame.height)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { frameChanged(notification) }
    func windowDidResize(_ notification: Notification) { frameChanged(notification) }

    private func frameChanged(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel else { return }
        updateFrame(panel.noteID, panel.frame)
    }

    // MARK: Persistence

    private func persist(_ id: UUID) {
        dirty.insert(id)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        for id in dirty {
            if let note = note(id) { try? store.save(note) }
        }
        dirty.removeAll()
    }
}

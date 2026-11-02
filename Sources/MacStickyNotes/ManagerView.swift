import AppKit
import StickyCore
import SwiftUI

/// The management window: browse, search, filter, tidy up and recover notes.
struct ManagerView: View {
    @ObservedObject var manager: NoteManager

    private enum Tab: Hashable { case notes, trash }

    @State private var tab: Tab = .notes
    @State private var query = NoteQuery()
    @State private var selection = Set<UUID>()
    @State private var confirmEmptyTrash = false

    private var source: [Note] { tab == .notes ? manager.activeNotes : manager.trashedNotes }
    private var visible: [Note] { query.apply(to: source) }

    /// Presets first, then any custom colours in use.
    private var colorChips: [NoteColor] {
        let used = Set(source.map(\.color))
        let customs = used.subtracting(NoteColor.presets).sorted { $0.hex < $1.hex }
        return NoteColor.presets.filter(used.contains) + customs
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if !selection.isEmpty {
                Divider()
                selectionBar
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .onChange(of: tab) { _, _ in selection.removeAll() }
        .confirmationDialog(L("Empty the trash?"), isPresented: $confirmEmptyTrash) {
            Button(L("Delete Forever"), role: .destructive) { manager.emptyTrash(); selection.removeAll() }
        } message: {
            Text(L("These notes cannot be recovered."))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text("\(L("Notes")) (\(manager.activeNotes.count))").tag(Tab.notes)
                    Text("\(L("Trash")) (\(manager.trashedNotes.count))").tag(Tab.trash)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Search"), text: $query.text).textFieldStyle(.plain)
                    if !query.text.isEmpty {
                        Button { query.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Menu {
                    Picker(L("Sort"), selection: $query.sort) {
                        Text(L("Recently Edited")).tag(NoteSort.modifiedDescending)
                        Text(L("Recently Created")).tag(NoteSort.createdDescending)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L("Sort"), systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if tab == .notes {
                    Button { manager.createNote() } label: { Label(L("New Note"), systemImage: "plus") }
                } else {
                    Button(role: .destructive) { confirmEmptyTrash = true } label: {
                        Label(L("Empty Trash"), systemImage: "trash")
                    }
                    .disabled(manager.trashedNotes.isEmpty)
                }
            }

            HStack(spacing: 8) {
                chip(nil)
                ForEach(colorChips, id: \.self) { chip($0) }
                Spacer()
                if tab == .trash {
                    Text(L("Notes in the trash are deleted after 30 days."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private func chip(_ color: NoteColor?) -> some View {
        let selected = query.color == color
        return Button {
            query.color = color
        } label: {
            Group {
                if let color {
                    Circle().fill(color.swiftUIColor).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Text(L("All")).font(.caption)
                }
            }
            .padding(.horizontal, color == nil ? 8 : 3)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(color?.presetName ?? (color == nil ? L("All colors") : L("Custom color")))
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: tab == .notes ? "note.text" : "trash").font(.largeTitle).foregroundStyle(.tertiary)
                Text(emptyMessage).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)], spacing: 14) {
                    ForEach(visible) { note in
                        card(note)
                    }
                }
                .padding(14)
            }
        }
    }

    private var emptyMessage: String {
        if !query.text.isEmpty || query.color != nil { return L("No matching notes") }
        return tab == .notes ? L("No notes yet") : L("The trash is empty")
    }

    private func card(_ note: Note) -> some View {
        let ink: Color = note.color.prefersLightText ? .white : .black
        let isSelected = selection.contains(note.id)

        return VStack(alignment: .leading, spacing: 6) {
            Text(note.previewText.isEmpty ? " " : String(note.previewText.prefix(220)))
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .lineLimit(6)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)

            HStack(spacing: 4) {
                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                if note.alwaysOnTop { Image(systemName: "pin.fill") }
                if note.isCollapsed && !note.isInTrash { Image(systemName: "eye.slash") }
            }
            .font(.caption2)
            .foregroundStyle(ink.opacity(0.55))
        }
        .padding(10)
        .background(note.color.swiftUIColor, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor, .white)
                    .padding(4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !note.isInTrash { manager.reopen(note.id) } }
        .onTapGesture { toggle(note.id) }
        .contextMenu { cardMenu(note) }
    }

    private func toggle(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if selection == [id] {
            selection.removeAll()
        } else {
            selection = [id]
        }
    }

    @ViewBuilder
    private func cardMenu(_ note: Note) -> some View {
        if note.isInTrash {
            Button(L("Restore")) { manager.restore(note.id) }
            Button(L("Delete Forever"), role: .destructive) { manager.deletePermanently(note.id) }
        } else {
            Button(L("Show on Desktop")) { manager.reopen(note.id) }
            Menu(L("Change Color")) { colorMenu(for: [note.id]) }
            Button(L("Move to Trash")) { manager.moveToTrash(note.id) }
        }
    }

    // MARK: Selection actions

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text(String(format: L("%d selected"), selection.count)).foregroundStyle(.secondary)
            Spacer()
            if tab == .notes {
                Menu(L("Change Color")) { colorMenu(for: Array(selection)) }.fixedSize()
                Button(L("Move to Trash")) {
                    for id in selection { manager.moveToTrash(id) }
                    selection.removeAll()
                }
            } else {
                Button(L("Restore")) {
                    for id in selection { manager.restore(id) }
                    selection.removeAll()
                }
                Button(L("Delete Forever"), role: .destructive) {
                    for id in selection { manager.deletePermanently(id) }
                    selection.removeAll()
                }
            }
            Button(L("Select None")) { selection.removeAll() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func colorMenu(for ids: [UUID]) -> some View {
        ForEach(NoteColor.presets, id: \.self) { color in
            Button(color.presetName ?? "") {
                for id in ids { manager.setColor(id, color) }
            }
        }
        Divider()
        Button(L("Custom Color…")) {
            let initial = ids.first.flatMap { manager.note($0)?.color }.map { NSColor($0) } ?? .yellow
            ColorPanelBridge.shared.present(initial: initial) { picked in
                Task { @MainActor in
                    for id in ids { manager.setColor(id, NoteColor(nsColor: picked)) }
                }
            }
        }
    }
}

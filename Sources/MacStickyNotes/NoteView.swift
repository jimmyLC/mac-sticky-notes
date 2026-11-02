import AppKit
import StickyCore
import SwiftUI

/// One sticky note: flat pastel sheet, thin title strip, and a toolbar that appears on hover.
struct NoteView: View {
    @ObservedObject var manager: NoteManager
    @ObservedObject var settings: AppSettings
    let noteID: UUID

    @State private var hovering = false
    @State private var showColors = false

    var body: some View {
        if let note = manager.note(noteID) {
            sheet(for: note)
        } else {
            Color.clear
        }
    }

    private func sheet(for note: Note) -> some View {
        let ink: Color = note.color.prefersLightText ? .white : .black

        return ZStack(alignment: .topLeading) {
            note.color.swiftUIColor

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.4))
                    Text(note.title.isEmpty ? L("Note") : note.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(WindowDragHandle())

                Divider().overlay(ink.opacity(0.15)).padding(.horizontal, 8)

                RichTextEditor(
                    initialMarkdown: note.markdown,
                    fontSize: settings.textSize.points,
                    textColor: note.color.prefersLightText ? .white : .black,
                    onChange: { manager.setMarkdown(noteID, $0) }
                )
                .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering { toolbar(for: note).padding(.top, 3).padding(.trailing, 6) }
        }
        .onHover { hovering = $0 }
        .contextMenu { contextMenu(for: note) }
    }

    // MARK: Toolbar

    private func toolbar(for note: Note) -> some View {
        HStack(spacing: 8) {
            toolbarButton("plus", help: L("New Note")) { manager.createNote() }

            Button { showColors.toggle() } label: {
                Circle()
                    .fill(note.color.swiftUIColor)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.45), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Change Color"))
            .popover(isPresented: $showColors, arrowEdge: .bottom) { colorPicker(for: note) }

            toolbarButton(note.alwaysOnTop ? "pin.fill" : "pin", help: L("Keep on Top")) { manager.togglePin(noteID) }
            toolbarButton("trash", help: L("Delete Note")) { manager.moveToTrash(noteID) }
            toolbarButton("xmark", help: L("Close Note")) { manager.collapse(noteID) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorPicker(for note: Note) -> some View {
        HStack(spacing: 10) {
            ForEach(NoteColor.presets, id: \.self) { color in
                Button {
                    manager.setColor(noteID, color)
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.3), lineWidth: 1))
                        .overlay {
                            if color == note.color {
                                Circle().strokeBorder(.primary.opacity(0.8), lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.presetName ?? "")
            }
            Divider().frame(height: 18)
            Button {
                showColors = false
                let id = noteID
                let manager = manager
                ColorPanelBridge.shared.present(initial: NSColor(note.color)) { picked in
                    Task { @MainActor in manager.setColor(id, NoteColor(nsColor: picked)) }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L("Custom Color…"))
        }
        .padding(12)
    }

    @ViewBuilder
    private func contextMenu(for note: Note) -> some View {
        Button(L("New Note")) { manager.createNote() }
        Divider()
        Toggle(L("Keep on Top"), isOn: Binding(get: { note.alwaysOnTop }, set: { _ in manager.togglePin(noteID) }))
        Toggle(L("Show on All Desktops"), isOn: Binding(get: { note.showOnAllSpaces }, set: { _ in manager.toggleAllSpaces(noteID) }))
        Divider()
        Button(L("Close Note")) { manager.collapse(noteID) }
        Button(L("Delete Note")) { manager.moveToTrash(noteID) }
    }
}

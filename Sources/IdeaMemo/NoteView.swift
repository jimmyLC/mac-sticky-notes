import AppKit
import StickyCore
import SwiftUI

/// One memo: flat pastel sheet, thin title strip, and a toolbar that appears on hover.
/// Double-click the title strip to roll it up to just the title.
struct NoteView: View {
    @ObservedObject var manager: NoteManager
    @ObservedObject var settings: AppSettings
    let noteID: UUID

    @Environment(\.colorScheme) private var colorScheme
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
        let shown = note.color.displayColor(dark: colorScheme == .dark)
        let ink: Color = shown.prefersLightText ? .white : .black

        return ZStack(alignment: .topLeading) {
            shown.swiftUIColor.opacity(note.opacity)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.4))
                    Text(note.title.isEmpty ? L("Idea") : note.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: NoteManager.shadedHeight)
                .overlay(WindowDragHandle(onDoubleClick: { manager.toggleShade(noteID) }))
                .help(L("Double-click to roll up"))

                if !note.isShaded {
                    Divider().overlay(ink.opacity(0.15)).padding(.horizontal, 8)

                    RichTextEditor(
                        initialMarkdown: note.markdown,
                        fontSize: settings.textSize.points,
                        textColor: shown.prefersLightText ? .white : .black,
                        onChange: { manager.setMarkdown(noteID, $0) }
                    )
                    .padding(.bottom, 4)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering || showColors {
                VStack(alignment: .trailing, spacing: 6) {
                    toolbar(for: note)
                    if showColors && !note.isShaded { colorPicker(for: note) }
                }
                .padding(.top, 3)
                .padding(.trailing, 6)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { contextMenu(for: note) }
    }

    // MARK: Toolbar

    private func toolbar(for note: Note) -> some View {
        HStack(spacing: 8) {
            toolbarButton("plus", help: L("New Memo")) { manager.createNote() }

            Button { showColors.toggle() } label: {
                Circle()
                    .fill(note.color.swiftUIColor)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.45), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Color and Transparency"))

            toolbarButton(note.alwaysOnTop ? "pin.fill" : "pin", help: L("Keep on Top")) { manager.togglePin(noteID) }

            if !note.isShaded {
                Menu {
                    Button(L("Bulleted List")) { manager.applyList(noteID, .bullet) }
                    Button(L("Numbered List")) { manager.applyList(noteID, .numbered) }
                    Button(L("Checklist")) { manager.applyList(noteID, .checklist) }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Lists"))
            }

            toolbarButton("trash", help: L("Delete Memo")) { manager.moveToTrash(noteID) }
            toolbarButton("xmark", help: L("Close Memo")) { manager.collapse(noteID) }
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
        VStack(spacing: 8) {
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

            HStack(spacing: 8) {
                Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { note.opacity }, set: { manager.setOpacity(noteID, $0) }),
                    in: 0.35...1
                )
                .controlSize(.small)
                .frame(width: 130)
                Image(systemName: "circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .help(L("Transparency"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func contextMenu(for note: Note) -> some View {
        Button(L("New Memo")) { manager.createNote() }
        Divider()
        Button(note.isShaded ? L("Unroll") : L("Roll Up")) { manager.toggleShade(noteID) }
        Toggle(L("Keep on Top"), isOn: Binding(get: { note.alwaysOnTop }, set: { _ in manager.togglePin(noteID) }))
        Toggle(L("Show on All Desktops"), isOn: Binding(get: { note.showOnAllSpaces }, set: { _ in manager.toggleAllSpaces(noteID) }))
        Divider()
        Button(L("Close Memo")) { manager.collapse(noteID) }
        Button(L("Delete Memo")) { manager.moveToTrash(noteID) }
    }
}

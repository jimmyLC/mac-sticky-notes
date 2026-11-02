import AppKit
import Carbon.HIToolbox
import StickyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let manager: NoteManager

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var exportMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        do { try LoginItem.set(wanted) } catch { launchAtLogin = LoginItem.isEnabled }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("Show in Dock"), isOn: $settings.showInDock)
                    Text(L("Turn off to keep Idea Memo in the menu bar only."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker(L("Text size"), selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent(L("New note shortcut")) {
                    HotkeyRecorder(chord: $settings.hotkey)
                        .frame(width: 120, height: 24)
                }
            }

            Section(L("Data")) {
                LabeledContent(L("Notes folder")) {
                    Button(L("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([manager.store.directory])
                    }
                }
                LabeledContent(L("Export all notes as Markdown")) {
                    Button(L("Export…")) { export() }
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("A backup of your notes is made once a day; the last 7 are kept."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let count = try manager.exportAll(to: folder)
            exportMessage = String(format: L("Exported %d notes."), count)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            exportMessage = L("Export failed.")
        }
    }
}

/// A button that records a key combination (at least one of ⌃ ⌥ ⌘ is required).
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var chord: HotkeyChord

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.onRecord = { context.coordinator.parent.chord = $0 }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        context.coordinator.parent = self
        button.shownChord = chord
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator {
        var parent: HotkeyRecorder
        init(parent: HotkeyRecorder) { self.parent = parent }
    }

    final class RecorderButton: NSButton {
        var onRecord: ((HotkeyChord) -> Void)?
        var shownChord = HotkeyChord.default { didSet { refreshTitle() } }
        private var recording = false { didSet { refreshTitle() } }

        override var acceptsFirstResponder: Bool { true }

        private func refreshTitle() {
            title = recording ? L("Type shortcut…") : shownChord.display
        }

        override func mouseDown(with event: NSEvent) {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            capture(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            capture(event)
        }

        private func capture(_ event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                recording = false
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbon: UInt32 = 0
            var glyphs = ""
            if flags.contains(.control) { carbon |= UInt32(controlKey); glyphs += "⌃" }
            if flags.contains(.option) { carbon |= UInt32(optionKey); glyphs += "⌥" }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey); glyphs += "⇧" }
            if flags.contains(.command) { carbon |= UInt32(cmdKey); glyphs += "⌘" }
            guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else {
                NSSound.beep()
                return
            }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            let chord = HotkeyChord(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbon,
                display: glyphs + (key.isEmpty ? "#\(event.keyCode)" : key)
            )
            recording = false
            shownChord = chord
            onRecord?(chord)
        }
    }
}

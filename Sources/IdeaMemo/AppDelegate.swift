import AppKit
import Combine
import StickyCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = AppSettings()
    private var manager: NoteManager!
    private var statusItem: NSStatusItem!
    private var managerWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let hotkey = GlobalHotkey()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            manager = NoteManager(store: try NoteStore(directory: Self.notesDirectory()), settings: settings)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = makeMainMenu()
        applyDockPolicy()
        setUpStatusItem()
        manager.start()
        registerHotkey()
        runExportHookIfRequested()

        settings.$hotkey
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.registerHotkey() } }
            .store(in: &cancellables)

        settings.$showInDock
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyDockPolicy(reactivate: true) } }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.askAboutLaunchAtLoginOnce() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching the app again while it runs (Finder, Spotlight) brings everything forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager.showAll()
        if !flag { openManager() }
        return true
    }

    /// Right-click menu on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: L("New Note"), action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Manage Notes…"), action: #selector(openManager), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: "").target = self
        return menu
    }

    // MARK: Dock icon

    /// Dock icon on (regular app) or menu bar only (accessory app).
    private func applyDockPolicy(reactivate: Bool = false) {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        // Switching policy drops focus; bring the window the user is working in back.
        if reactivate {
            NSApp.activate(ignoringOtherApps: true)
            (settingsWindow ?? NSApp.windows.first { $0.isVisible })?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Data location

    private static func notesDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["MACSTICKY_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("Notes")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("IdeaMemo", isDirectory: true).appendingPathComponent("Notes")
    }

    /// Developer hook: `--export-to <folder>` exports all notes at launch and logs the result,
    /// so the sandboxed export path can be checked without the folder picker.
    private func runExportHookIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--export-to"), flag + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        do {
            let count = try manager.exportAll(to: folder)
            NSLog("IdeaMemo export: wrote %d notes to %@", count, folder.path)
        } catch {
            NSLog("IdeaMemo export failed: %@", String(describing: error))
        }
    }

    // MARK: Hotkey and login

    private func registerHotkey() {
        let ok = hotkey.register(settings.hotkey) { [weak self] in self?.newNote() }
        if !ok { NSSound.beep() }
    }

    /// The App Store requires consent before launching at login, so ask once, preselected.
    private func askAboutLaunchAtLoginOnce() {
        guard !settings.hasAskedLaunchAtLogin, !CommandLine.arguments.contains("--skip-login-prompt") else { return }
        settings.hasAskedLaunchAtLogin = true

        let alert = NSAlert()
        alert.messageText = L("Open Idea Memo when you log in?")
        alert.informativeText = L("Your notes will be waiting on the desktop. You can change this in Settings.")
        alert.addButton(withTitle: L("OK"))
        let checkbox = NSButton(checkboxWithTitle: L("Launch at login"), target: nil, action: nil)
        checkbox.state = .on
        alert.accessoryView = checkbox
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if checkbox.state == .on { try? LoginItem.set(true) }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: L("Idea Memo"))
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: L("New Note"), action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Show All Notes"), action: #selector(showAllNotes), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Manage Notes…"), action: #selector(openManager), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Idea Memo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    // MARK: Actions

    @objc private func newNote() { manager.createNote() }
    @objc private func showAllNotes() { manager.showAll() }

    @objc private func openManager() {
        if managerWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Manage Notes")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ManagerView(manager: manager))
            window.center()
            window.setFrameAutosaveName("ManagerWindow")
            managerWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        managerWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Settings")
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView(settings: settings, manager: manager))
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func closeCurrentNote() {
        if let panel = NSApp.keyWindow as? NotePanel {
            manager.collapse(panel.noteID)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    @objc private func increaseTextSize() { settings.textSize = settings.textSize.larger }
    @objc private func decreaseTextSize() { settings.textSize = settings.textSize.smaller }

    // MARK: Main menu

    /// An accessory app has no visible menu bar, but this menu still powers ⌘C, ⌘V, ⌘Z and friends.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        func add(_ title: String, to menu: NSMenu, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            item.submenu = submenu
            menu.addItem(item)
        }
        func item(_ title: String, _ action: Selector?, _ key: String, target: AnyObject? = nil,
                  modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }

        add(L("Idea Memo"), to: main, [
            item(L("Settings…"), #selector(openSettings), ",", target: self),
            .separator(),
            item(L("Quit Idea Memo"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        add(L("File"), to: main, [
            item(L("New Note"), #selector(newNote), "n", target: self),
            item(L("Close Note"), #selector(closeCurrentNote), "w", target: self),
        ])
        add(L("Edit"), to: main, [
            item(L("Undo"), Selector(("undo:")), "z"),
            item(L("Redo"), Selector(("redo:")), "z", modifiers: [.command, .shift]),
            .separator(),
            item(L("Cut"), #selector(NSText.cut(_:)), "x"),
            item(L("Copy"), #selector(NSText.copy(_:)), "c"),
            item(L("Paste"), #selector(NSText.paste(_:)), "v"),
            item(L("Select All"), #selector(NSText.selectAll(_:)), "a"),
        ])
        add(L("Format"), to: main, [
            item(L("Bold"), #selector(RichNoteTextView.toggleBold(_:)), "b"),
            item(L("Italic"), #selector(RichNoteTextView.toggleItalic(_:)), "i"),
        ])
        add(L("View"), to: main, [
            item(L("Larger Text"), #selector(increaseTextSize), "+", target: self),
            item(L("Smaller Text"), #selector(decreaseTextSize), "-", target: self),
        ])
        return main
    }
}

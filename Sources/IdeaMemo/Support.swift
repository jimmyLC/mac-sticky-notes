import AppKit
import Carbon.HIToolbox
import ServiceManagement
import StickyCore
import SwiftUI

/// Looks up a UI string. English text is the key; `zh-Hant.lproj` provides the translation.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

extension NSColor {
    convenience init(_ color: NoteColor) {
        let c = color.components
        self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
}

extension NoteColor {
    init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.sRGB) ?? .yellow
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }

    var swiftUIColor: Color { Color(nsColor: NSColor(self)) }

    /// Localized name for the four presets; custom colours have none.
    var presetName: String? {
        switch self {
        case .yellow: return L("Yellow")
        case .pink: return L("Pink")
        case .blue: return L("Blue")
        case .green: return L("Green")
        default: return nil
        }
    }
}

// MARK: Settings

enum TextSize: Int, CaseIterable, Identifiable {
    case small = 12
    case medium = 14
    case large = 16

    var id: Int { rawValue }
    var points: CGFloat { CGFloat(rawValue) }

    var label: String {
        switch self {
        case .small: return L("Small")
        case .medium: return L("Medium")
        case .large: return L("Large")
        }
    }

    var larger: TextSize { self == .small ? .medium : .large }
    var smaller: TextSize { self == .large ? .medium : .small }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("System")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Upgrade {
    /// Purchasing is not built yet; this tells the user so instead of doing nothing.
    @MainActor
    static func present() {
        let alert = NSAlert()
        alert.messageText = L("Pro is coming soon")
        alert.informativeText = L("Unlimited memos will be available with Pro. Purchasing is not open yet.")
        alert.addButton(withTitle: L("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

struct HotkeyChord: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    /// ⌃⌥N
    static let `default` = HotkeyChord(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥N"
    )
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: "textSize") }
    }

    @Published var hotkey: HotkeyChord {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: "hotkey") }
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }

    /// Pro is a placeholder switch until purchasing is built; `--pro` unlocks it for testing.
    @Published var isPro: Bool {
        didSet { defaults.set(isPro, forKey: "isPro") }
    }

    var plan: Plan { isPro ? .pro : .free }

    /// Dock icon on by default; off keeps the app in the menu bar only.
    @Published var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: "showInDock") }
    }

    var hasAskedLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "hasAskedLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "hasAskedLaunchAtLogin") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textSize = TextSize(rawValue: defaults.integer(forKey: "textSize")) ?? .medium
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        isPro = defaults.bool(forKey: "isPro") || CommandLine.arguments.contains("--pro")
        hotkey = defaults.data(forKey: "hotkey")
            .flatMap { try? JSONDecoder().decode(HotkeyChord.self, from: $0) } ?? .default
    }
}

// MARK: System integration

/// One global hotkey through Carbon, which works inside the App Sandbox.
final class GlobalHotkey {
    private static var action: (() -> Void)?
    private static var handlerInstalled = false
    private var reference: EventHotKeyRef?

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    @discardableResult
    func register(_ chord: HotkeyChord, action: @escaping () -> Void) -> Bool {
        unregister()
        Self.installHandlerIfNeeded()
        Self.action = action
        let id = EventHotKeyID(signature: OSType(0x4D534E48), id: 1)
        let status = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers, id, GetApplicationEventTarget(), 0, &reference)
        return status == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Shows the shared system colour panel and forwards live changes.
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var handler: ((NSColor) -> Void)?

    func present(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        handler = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        handler?(sender.color)
    }
}

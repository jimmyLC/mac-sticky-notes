import AppKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // The Dock icon is applied from the saved setting in applicationDidFinishLaunching.
    application.setActivationPolicy(.regular)
    application.run()
}
